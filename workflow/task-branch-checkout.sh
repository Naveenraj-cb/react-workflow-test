#!/bin/bash

# Task Branch Checkout Script
# This script creates GitHub branches from Linear issues and checks them out locally

set -e

# Load environment variables from .env.local
if [[ -f "$(dirname "$0")/.env.local" ]]; then
    source "$(dirname "$0")/.env.local"
fi
DEFAULT_BASE_BRANCH="main"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to print colored output
print_status() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Function to check if required tools are installed
check_prerequisites() {
    print_status "Checking prerequisites..."
    
    if ! command -v curl &> /dev/null; then
        print_error "curl is required but not installed"
        exit 1
    fi
    
    if ! command -v jq &> /dev/null; then
        print_error "jq is required but not installed. Please install jq first."
        echo "  macOS: brew install jq"
        echo "  Ubuntu: sudo apt-get install jq"
        echo "  Windows: Download from https://stedolan.github.io/jq/"
        exit 1
    fi
    
    if ! command -v git &> /dev/null; then
        print_error "git is required but not installed"
        exit 1
    fi
    
    print_success "All prerequisites are installed"
}

# Function to validate environment variables
check_config() {
    print_status "Checking configuration..."
    
    if [[ -z "$LINEAR_API_TOKEN" || "$LINEAR_API_TOKEN" == "your_linear_api_token_here" ]]; then
        print_error "LINEAR_API_TOKEN not set. Please set it in .env.local file."
        echo "Get your token from: https://linear.app/settings/api"
        exit 1
    fi
    
    if [[ -z "$GITHUB_TOKEN" || "$GITHUB_TOKEN" == "your_github_token_here" ]]; then
        print_error "GITHUB_TOKEN not set. Please set it in .env.local file."
        echo "Get your token from: https://github.com/settings/tokens"
        exit 1
    fi
    
    if [[ -z "$GITHUB_REPO" ]]; then
        print_error "GITHUB_REPO not set. Please set it in .env.local file."
        echo "Format: owner/repository-name"
        exit 1
    fi
    
    print_success "Configuration is valid"
}

# Function to get Linear issue details
get_linear_issue() {
    local issue_id="$1"
    
    print_status "Fetching Linear issue: $issue_id" >&2
    
    local query='{
        "query": "query GetIssue($id: String!) { issue(id: $id) { id identifier title description state { name } team { key } labels { nodes { name } } } }",
        "variables": { "id": "'$issue_id'" }
    }'
    
    local response=$(curl -s -X POST \
        -H "Authorization: $LINEAR_API_TOKEN" \
        -H "Content-Type: application/json" \
        -d "$query" \
        "https://api.linear.app/graphql")
    
    
    # Check if response is valid JSON
    if ! echo "$response" | jq . > /dev/null 2>&1; then
        print_error "Invalid JSON response from Linear API"
        echo "Response: $response"
        exit 1
    fi
    
    if echo "$response" | jq -e '.errors' > /dev/null; then
        print_error "Failed to fetch Linear issue: $(echo "$response" | jq -r '.errors[0].message')"
        exit 1
    fi
    
    echo "$response" | jq -r '.data.issue'
}

# Function to create GitHub branch
create_github_branch() {
    local branch_name="$1"
    local base_branch="$2"
    
    print_status "Creating GitHub branch: $branch_name from $base_branch"
    
    # Get the SHA of the base branch
    local base_response=$(curl -s \
        -H "Authorization: Bearer $GITHUB_TOKEN" \
        -H "Accept: application/vnd.github+json" \
        -H "X-GitHub-Api-Version: 2022-11-28" \
        "https://api.github.com/repos/$GITHUB_REPO/git/refs/heads/$base_branch")
    
    
    local base_sha=$(echo "$base_response" | jq -r '.object.sha')
    
    if [[ "$base_sha" == "null" ]]; then
        print_error "Failed to get SHA for base branch: $base_branch"
        echo "Response: $base_response"
        exit 1
    fi
    
    # Create the new branch
    local create_response=$(curl -s -X POST \
        -H "Authorization: Bearer $GITHUB_TOKEN" \
        -H "Accept: application/vnd.github+json" \
        -H "X-GitHub-Api-Version: 2022-11-28" \
        "https://api.github.com/repos/$GITHUB_REPO/git/refs" \
        -d "{
            \"ref\": \"refs/heads/$branch_name\",
            \"sha\": \"$base_sha\"
        }")
    
    
    if echo "$create_response" | jq -e '.message' > /dev/null; then
        local error_msg=$(echo "$create_response" | jq -r '.message')
        if [[ "$error_msg" == *"already exists"* ]]; then
            print_warning "Branch $branch_name already exists"
            return 0
        else
            print_error "Failed to create branch: $error_msg"
            echo "Full response: $create_response"
            exit 1
        fi
    fi
    
    print_success "Branch created: $branch_name"
}

# Function to update Linear issue with branch link
update_linear_issue() {
    local issue_id="$1"
    local branch_name="$2"
    
    print_status "Adding branch link as comment to Linear issue"
    
    local branch_url="https://github.com/$GITHUB_REPO/tree/$branch_name"
    local comment_body="🌿 **Branch created:** [$branch_name]($branch_url)\n\nThis branch is ready for development. You can start working on this issue!"
    
    local mutation='{
        "query": "mutation CreateComment($input: CommentCreateInput!) { commentCreate(input: $input) { success comment { id } } }",
        "variables": {
            "input": {
                "issueId": "'$issue_id'",
                "body": "'$comment_body'"
            }
        }
    }'
    
    local response=$(curl -s -X POST \
        -H "Authorization: $LINEAR_API_TOKEN" \
        -H "Content-Type: application/json" \
        -d "$mutation" \
        "https://api.linear.app/graphql")
    
    if echo "$response" | jq -e '.errors' > /dev/null; then
        print_warning "Could not add comment to Linear issue: $(echo "$response" | jq -r '.errors[0].message')"
    else
        print_success "Branch link added as comment to Linear issue"
    fi
}

# Function to checkout branch locally
checkout_branch_locally() {
    local branch_name="$1"
    local base_branch="$2"
    
    print_status "Checking out branch locally"
    
    # Fetch latest changes
    git fetch origin
    
    # Check if we're in a git repository
    if ! git rev-parse --git-dir > /dev/null 2>&1; then
        print_error "Not in a git repository"
        exit 1
    fi
    
    # Switch to base branch and pull latest
    git checkout "$base_branch"
    git pull origin "$base_branch"
    
    # Create and checkout the new branch
    if git show-ref --verify --quiet "refs/heads/$branch_name"; then
        print_warning "Local branch $branch_name already exists, checking out"
        git checkout "$branch_name"
    else
        git checkout -b "$branch_name" "origin/$branch_name"
        print_success "Checked out new branch: $branch_name"
    fi
}

# Function to generate branch name from Linear issue
generate_branch_name() {
    local issue_data="$1"
    
    
    # Extract values with fallbacks and error checking
    local issue_identifier=$(echo "$issue_data" | jq -r '.identifier // "unknown"' 2>/dev/null)
    
    # Check if jq parsing failed
    if [[ $? -ne 0 ]]; then
        print_error "Failed to parse issue data with jq"
        return 1
    fi
    
    # Determine branch type based on labels
    local labels=$(echo "$issue_data" | jq -r '.labels.nodes[].name // empty' 2>/dev/null | tr '\n' ' ')
    local branch_type="feature"
    
    if [[ "$labels" == *"bug"* ]]; then
        branch_type="bugfix"
    elif [[ "$labels" == *"hotfix"* ]]; then
        branch_type="hotfix"
    elif [[ "$labels" == *"chore"* ]]; then
        branch_type="chore"
    fi
    
    local branch_name="${branch_type}/${issue_identifier}"
    echo "$branch_name"
}

# Main function
main() {
    echo "🔗 Task Branch Checkout Tool"
    echo "=================================="
    
    # Parse command line arguments
    local issue_id=""
    local base_branch="$DEFAULT_BASE_BRANCH"
    local skip_checkout=false
    
    while [[ $# -gt 0 ]]; do
        case $1 in
            -i|--issue)
                issue_id="$2"
                shift 2
                ;;
            -b|--base-branch)
                base_branch="$2"
                shift 2
                ;;
            --skip-checkout)
                skip_checkout=true
                shift
                ;;
            -h|--help)
                echo "Usage: $0 -i ISSUE_ID [-b BASE_BRANCH] [--skip-checkout]"
                echo ""
                echo "Options:"
                echo "  -i, --issue         Linear issue ID (required)"
                echo "  -b, --base-branch   Base branch to create from (default: main)"
                echo "  --skip-checkout     Don't checkout the branch locally"
                echo "  -h, --help          Show this help message"
                echo ""
                echo "Environment variables required:"
                echo "  LINEAR_API_TOKEN    Your Linear API token"
                echo "  GITHUB_TOKEN        Your GitHub personal access token"
                echo "  GITHUB_REPO         GitHub repository (format: owner/repo)"
                exit 0
                ;;
            *)
                print_error "Unknown option: $1"
                echo "Use -h or --help for usage information"
                exit 1
                ;;
        esac
    done
    
    if [[ -z "$issue_id" ]]; then
        print_error "Issue ID is required. Use -i or --issue to specify it."
        echo "Example: $0 -i ABC-123"
        exit 1
    fi
    
    # Run checks
    check_prerequisites
    check_config
    
    # Get Linear issue details
    local issue_data=$(get_linear_issue "$issue_id")
    
    if [[ "$issue_data" == "null" || -z "$issue_data" ]]; then
        print_error "Issue not found or failed to fetch: $issue_id"
        exit 1
    fi
    
    # Validate issue data contains required fields
    local issue_title=$(echo "$issue_data" | jq -r '.title // empty' 2>/dev/null)
    local issue_identifier=$(echo "$issue_data" | jq -r '.identifier // empty' 2>/dev/null)
    
    if [[ -z "$issue_title" || -z "$issue_identifier" ]]; then
        print_error "Invalid issue data received from Linear API"
        echo "Issue data: $issue_data"
        exit 1
    fi
    
    print_success "Found issue: $issue_title"
    
    # Generate branch name
    local branch_name=$(generate_branch_name "$issue_data")
    
    # Validate branch name was generated correctly
    if [[ "$branch_name" == *"/unknown" || -z "$branch_name" ]]; then
        print_error "Failed to generate valid branch name: $branch_name"
        echo "This usually indicates an issue with parsing the Linear API response."
        exit 1
    fi
    
    print_status "Generated branch name: $branch_name"
    
    # Create GitHub branch
    create_github_branch "$branch_name" "$base_branch"
    
    # Update Linear issue
    update_linear_issue "$issue_id" "$branch_name"
    
    # Checkout branch locally (unless skipped)
    if [[ "$skip_checkout" == false ]]; then
        checkout_branch_locally "$branch_name" "$base_branch"
    fi
    
    echo ""
    print_success "Integration complete!"
    echo "📋 Issue: $issue_title"
    echo "🌿 Branch: $branch_name"
    echo "🔗 GitHub: https://github.com/$GITHUB_REPO/tree/$branch_name"
    echo ""
    
    # Prompt user to run Claude prompt script
    echo "🤖 Would you like to prompt Claude with this task? (y/n)"
    read -r prompt_claude_response
    
    if [[ "$prompt_claude_response" =~ ^[Yy]$ ]]; then
        echo ""
        print_status "Launching Claude prompt..."
        # Pass the issue data directly to avoid another API call
        echo "$issue_data" | "$(dirname "$0")/prompt-claude.sh" --from-stdin
    else
        echo ""
        echo "Next steps:"
        echo "1. Start working on your feature"
        echo "2. Use (ai) and (dev) tags in commit messages"
        echo "3. Push changes: git push origin $branch_name"
        echo "4. Or run: ./workflow/prompt-claude.sh -i $issue_id"
    fi
}

# Run main function with all arguments
main "$@"