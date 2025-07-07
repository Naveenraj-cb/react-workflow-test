#!/bin/bash

# Raise PR Script
# This script pushes current branch to origin and creates a PR to the base branch

set -e

# Load environment variables from .env.local
if [[ -f "$(dirname "$0")/.env.local" ]]; then
    source "$(dirname "$0")/.env.local"
fi

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
    
    if ! command -v git &> /dev/null; then
        print_error "git is required but not installed"
        exit 1
    fi
    
    if ! command -v gh &> /dev/null; then
        print_error "GitHub CLI (gh) is required but not installed"
        echo "  Install from: https://cli.github.com/"
        echo "  macOS: brew install gh"
        echo "  Ubuntu: sudo apt install gh"
        exit 1
    fi
    
    if ! command -v curl &> /dev/null; then
        print_error "curl is required but not installed"
        exit 1
    fi
    
    if ! command -v jq &> /dev/null; then
        print_error "jq is required but not installed. Please install jq first."
        echo "  macOS: brew install jq"
        echo "  Ubuntu: sudo apt-get install jq"
        exit 1
    fi
    
    print_success "All prerequisites are installed"
}

# Function to validate environment variables
check_config() {
    print_status "Checking configuration..."
    
    # Check if GitHub CLI is authenticated
    if ! gh auth status &> /dev/null; then
        print_error "GitHub CLI not authenticated. Please run 'gh auth login' first."
        exit 1
    fi
    
    # LINEAR_API_TOKEN is optional - only warn if not set
    if [[ -z "$LINEAR_API_TOKEN" ]]; then
        print_warning "LINEAR_API_TOKEN not set. PR will be created without Linear issue details."
        print_warning "Set it in .env.local to include Linear issue title and description."
    fi
    
    print_success "Configuration is valid"
}

# Function to get Linear issue details
get_linear_issue() {
    local issue_id="$1"
    
    if [[ -z "$LINEAR_API_TOKEN" ]]; then
        echo "null"
        return
    fi
    
    print_status "Fetching Linear issue: $issue_id" >&2
    
    local query='{
        "query": "query GetIssue($id: String!) { issue(id: $id) { id identifier title description state { name id } team { key } labels { nodes { name } } } }",
        "variables": { "id": "'$issue_id'" }
    }'
    
    local response=$(curl -s -X POST \
        -H "Authorization: $LINEAR_API_TOKEN" \
        -H "Content-Type: application/json" \
        -d "$query" \
        "https://api.linear.app/graphql")
    
    # Check if response is valid JSON
    if ! echo "$response" | jq . > /dev/null 2>&1; then
        print_warning "Invalid JSON response from Linear API" >&2
        echo "null"
        return
    fi
    
    if echo "$response" | jq -e '.errors' > /dev/null; then
        print_warning "Failed to fetch Linear issue: $(echo "$response" | jq -r '.errors[0].message')" >&2
        echo "null"
        return
    fi
    
    echo "$response" | jq -r '.data.issue'
}

# Function to extract Linear issue ID from branch name
extract_issue_id_from_branch() {
    local branch_name="$1"
    
    # Try to extract issue ID from branch name patterns like:
    # - feature/COD-294
    # - feature/linear-COD-294-add-hello-world
    # - COD-294-some-description
    
    if [[ "$branch_name" =~ ([A-Z]+-[0-9]+) ]]; then
        echo "${BASH_REMATCH[1]}"
    else
        echo ""
    fi
}

# Function to create PR title and description
create_pr_content() {
    local issue_id="$1"
    local custom_title="$2"
    local custom_description="$3"
    local current_branch="$4"
    
    local pr_title=""
    local pr_description=""
    
    # If custom title/description provided, use them
    if [[ -n "$custom_title" ]]; then
        pr_title="$custom_title"
    fi
    
    if [[ -n "$custom_description" ]]; then
        pr_description="$custom_description"
    fi
    
    # Try to get Linear issue details if issue_id is provided
    if [[ -n "$issue_id" ]]; then
        local issue_data=$(get_linear_issue "$issue_id")
        
        if [[ "$issue_data" != "null" && -n "$issue_data" ]]; then
            local issue_title=$(echo "$issue_data" | jq -r '.title // empty')
            local issue_description=$(echo "$issue_data" | jq -r '.description // empty')
            local issue_identifier=$(echo "$issue_data" | jq -r '.identifier // empty')
            
            # Use Linear issue title if no custom title provided
            if [[ -z "$pr_title" && -n "$issue_title" ]]; then
                pr_title="$issue_title"
            fi
            
            # Create PR description with Linear issue details
            if [[ -z "$pr_description" ]]; then
                pr_description="## Overview\n"
                if [[ -n "$issue_title" ]]; then
                    pr_description+="**Linear Issue:** [$issue_identifier] $issue_title\n\n"
                fi
                if [[ -n "$issue_description" && "$issue_description" != "null" ]]; then
                    pr_description+="**Description:**\n$issue_description\n\n"
                fi
                pr_description+="## Changes\n"
                pr_description+="- Implementation completed in branch: \`$current_branch\`\n"
                pr_description+="- Please review the commits for detailed changes\n\n"
                pr_description+="## Testing\n"
                pr_description+="- [ ] Code builds successfully\n"
                pr_description+="- [ ] Tests pass\n"
                pr_description+="- [ ] Feature works as expected\n"
            fi
        fi
    fi
    
    # Fallback to branch name if no title found
    if [[ -z "$pr_title" ]]; then
        pr_title="$current_branch"
    fi
    
    # Fallback description if none provided
    if [[ -z "$pr_description" ]]; then
        pr_description="## Overview\n"
        pr_description+="Pull request for branch: \`$current_branch\`\n\n"
        pr_description+="## Changes\n"
        pr_description+="- Please review the commits for detailed changes\n\n"
        pr_description+="## Testing\n"
        pr_description+="- [ ] Code builds successfully\n"
        pr_description+="- [ ] Tests pass\n"
        pr_description+="- [ ] Feature works as expected\n"
    fi
    
    echo -e "$pr_title\n---\n$pr_description"
}

# Function to push branch and create PR
create_pull_request() {
    local current_branch="$1"
    local base_branch="$2"
    local pr_title="$3"
    local pr_description="$4"
    
    print_status "Pushing branch '$current_branch' to origin..."
    
    # Push current branch to origin
    if ! git push origin "$current_branch" 2>/dev/null; then
        print_error "Failed to push branch to origin"
        exit 1
    fi
    
    print_success "Branch pushed successfully"
    
    print_status "Creating pull request..."
    
    # Create PR using GitHub CLI
    local pr_url=$(gh pr create \
        --title "$pr_title" \
        --body "$pr_description" \
        --base "$base_branch" \
        --head "$current_branch" 2>/dev/null)
    
    if [[ $? -eq 0 && -n "$pr_url" ]]; then
        print_success "Pull request created successfully!"
        echo "=Ë Title: $pr_title"
        echo "<? Branch: $current_branch ’ $base_branch"
        echo "= URL: $pr_url"
        return 0
    else
        print_error "Failed to create pull request"
        exit 1
    fi
}

# Main function
main() {
    echo "=€ Raise PR Tool"
    echo "================"
    
    # Parse command line arguments
    local issue_id=""
    local base_branch="main"
    local custom_title=""
    local custom_description=""
    local auto_detect_issue=true
    
    while [[ $# -gt 0 ]]; do
        case $1 in
            -i|--issue)
                issue_id="$2"
                auto_detect_issue=false
                shift 2
                ;;
            -b|--base-branch)
                base_branch="$2"
                shift 2
                ;;
            -t|--title)
                custom_title="$2"
                shift 2
                ;;
            -d|--description)
                custom_description="$2"
                shift 2
                ;;
            --no-auto-detect)
                auto_detect_issue=false
                shift
                ;;
            -h|--help)
                echo "Usage: $0 [OPTIONS]"
                echo ""
                echo "Options:"
                echo "  -i, --issue ID          Linear issue ID (e.g., COD-294)"
                echo "  -b, --base-branch       Base branch for PR (default: main)"
                echo "  -t, --title             Custom PR title"
                echo "  -d, --description       Custom PR description"
                echo "  --no-auto-detect        Don't auto-detect issue ID from branch name"
                echo "  -h, --help              Show this help message"
                echo ""
                echo "Environment variables (optional):"
                echo "  LINEAR_API_TOKEN        Linear API token for issue details"
                echo ""
                echo "This script:"
                echo "1. Pushes current branch to origin"
                echo "2. Fetches Linear issue details (if available)"
                echo "3. Creates GitHub PR with proper title and description"
                echo "4. Displays PR URL"
                echo ""
                echo "Examples:"
                echo "  $0                          # Auto-detect issue from branch name"
                echo "  $0 -i COD-294              # Specify issue ID"
                echo "  $0 -b develop              # PR to develop branch"
                echo "  $0 -t \"Custom Title\"       # Custom PR title"
                exit 0
                ;;
            *)
                print_error "Unknown option: $1"
                echo "Use -h or --help for usage information"
                exit 1
                ;;
        esac
    done
    
    # Run checks
    check_prerequisites
    check_config
    
    # Get current branch
    local current_branch=$(git branch --show-current)
    
    if [[ -z "$current_branch" ]]; then
        print_error "Could not determine current branch"
        exit 1
    fi
    
    # Don't allow creating PR from base branch
    if [[ "$current_branch" == "$base_branch" ]]; then
        print_error "Cannot create PR from base branch '$base_branch'"
        print_error "Please checkout a feature branch first"
        exit 1
    fi
    
    print_status "Current branch: $current_branch"
    print_status "Base branch: $base_branch"
    
    # Auto-detect issue ID from branch name if not provided
    if [[ -z "$issue_id" && "$auto_detect_issue" == true ]]; then
        issue_id=$(extract_issue_id_from_branch "$current_branch")
        if [[ -n "$issue_id" ]]; then
            print_status "Auto-detected issue ID: $issue_id"
        else
            print_warning "Could not auto-detect issue ID from branch name"
        fi
    fi
    
    # Check if PR already exists
    local existing_pr=$(gh pr view --json url 2>/dev/null | jq -r '.url // empty')
    if [[ -n "$existing_pr" ]]; then
        print_warning "Pull request already exists for this branch"
        print_warning "URL: $existing_pr"
        echo ""
        read -p "Do you want to continue and update the existing PR? (y/N): " confirm
        if [[ "$confirm" != "y" && "$confirm" != "Y" ]]; then
            print_status "Cancelled by user"
            exit 0
        fi
    fi
    
    # Create PR content
    local pr_content=$(create_pr_content "$issue_id" "$custom_title" "$custom_description" "$current_branch")
    local pr_title=$(echo "$pr_content" | head -1)
    local pr_description=$(echo "$pr_content" | tail -n +3)
    
    # Create the pull request
    create_pull_request "$current_branch" "$base_branch" "$pr_title" "$pr_description"
    
    echo ""
    print_success "<‰ PR creation completed successfully!"
    
    if [[ -n "$issue_id" ]]; then
        echo ""
        print_status "=¡ Next steps:"
        echo "   1. Review the PR and make any necessary changes"
        echo "   2. Request reviews from team members"
        echo "   3. Merge the PR when approved"
        echo "   4. Run the complete-task script: ./complete-task.sh -i $issue_id"
    fi
}

# Run main function with all arguments
main "$@"