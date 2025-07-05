#!/bin/bash

# Prompt Claude Script
# This script prompts Claude with task title and description from Linear issue

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
    
    if ! command -v claude &> /dev/null; then
        print_error "claude CLI is required but not installed"
        echo "Install from: https://claude.ai/code"
        exit 1
    fi
    
    print_success "All prerequisites are installed"
}

# Function to validate environment variables
check_config() {
    print_status "Checking configuration..."
    
    if [[ -z "$LINEAR_API_TOKEN" ]]; then
        print_error "LINEAR_API_TOKEN not set. Please set it in .env.local file."
        echo "Get your token from: https://linear.app/settings/api"
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

# Function to create Claude prompt
create_claude_prompt() {
    local issue_data="$1"
    
    local issue_id=$(echo "$issue_data" | jq -r '.identifier')
    local title=$(echo "$issue_data" | jq -r '.title')
    local description=$(echo "$issue_data" | jq -r '.description // "No description provided"')
    local state=$(echo "$issue_data" | jq -r '.state.name')
    local team=$(echo "$issue_data" | jq -r '.team.key')
    
    # Get current branch name
    local current_branch=$(git branch --show-current 2>/dev/null || echo "unknown")
    
    cat << EOF
I'm working on a Linear issue and need your help to implement it.

**Issue Details:**
- ID: $issue_id
- Title: $title
- Description: $description
- State: $state
- Team: $team
- Current Branch: $current_branch

**Request:**
Please help me implement this task. Analyze the requirements and provide guidance on:
1. What files need to be created or modified
2. The implementation approach
3. Any dependencies or considerations
4. Step-by-step implementation plan

Please start by understanding the codebase structure and then provide your recommendations.
EOF
}

# Function to prompt Claude
prompt_claude() {
    local prompt="$1"
    
    print_status "Prompting Claude with task details..."
    
    # Create a temporary file for the prompt
    local temp_file=$(mktemp)
    echo "$prompt" > "$temp_file"
    
    # Launch Claude with the prompt
    if command -v claude &> /dev/null; then
        claude < "$temp_file"
        local claude_exit_code=$?
        
        # Clean up
        rm "$temp_file"
        
        if [[ $claude_exit_code -eq 0 ]]; then
            print_success "Claude session completed"
        else
            print_warning "Claude session ended with exit code: $claude_exit_code"
        fi
    else
        print_error "Claude CLI not found. Please install it first."
        echo "Prompt content:"
        echo "==============="
        cat "$temp_file"
        rm "$temp_file"
        exit 1
    fi
}

# Main function
main() {
    echo "🤖 Claude Task Prompt Tool"
    echo "=========================="
    
    # Parse command line arguments
    local issue_id=""
    local from_stdin=false
    
    while [[ $# -gt 0 ]]; do
        case $1 in
            -i|--issue)
                issue_id="$2"
                shift 2
                ;;
            --from-stdin)
                from_stdin=true
                shift
                ;;
            -h|--help)
                echo "Usage: $0 -i ISSUE_ID | $0 --from-stdin"
                echo ""
                echo "Options:"
                echo "  -i, --issue         Linear issue ID (required for API fetch)"
                echo "  --from-stdin        Read issue data from stdin (no API call)"
                echo "  -h, --help          Show this help message"
                echo ""
                echo "Environment variables required (only for -i mode):"
                echo "  LINEAR_API_TOKEN    Your Linear API token"
                echo ""
                echo "This script prompts Claude with Linear issue details."
                echo "Can fetch from API or receive data from stdin."
                exit 0
                ;;
            *)
                print_error "Unknown option: $1"
                echo "Use -h or --help for usage information"
                exit 1
                ;;
        esac
    done
    
    local issue_data=""
    
    if [[ "$from_stdin" == true ]]; then
        # Read issue data from stdin
        print_status "Reading issue data from stdin..."
        issue_data=$(cat)
        
        if [[ -z "$issue_data" ]]; then
            print_error "No issue data received from stdin"
            exit 1
        fi
        
        # Only check prerequisites for Claude
        if ! command -v claude &> /dev/null; then
            print_error "claude CLI is required but not installed"
            echo "Install from: https://claude.ai/code"
            exit 1
        fi
    else
        # Fetch from API
        if [[ -z "$issue_id" ]]; then
            print_error "Issue ID is required. Use -i or --issue to specify it."
            echo "Example: $0 -i COD-294"
            exit 1
        fi
        
        # Run checks
        check_prerequisites
        check_config
        
        # Get Linear issue details
        issue_data=$(get_linear_issue "$issue_id")
        
        if [[ "$issue_data" == "null" || -z "$issue_data" ]]; then
            print_error "Issue not found or failed to fetch: $issue_id"
            exit 1
        fi
    fi
    
    # Validate issue data contains required fields
    local issue_title=$(echo "$issue_data" | jq -r '.title // empty' 2>/dev/null)
    local issue_identifier=$(echo "$issue_data" | jq -r '.identifier // empty' 2>/dev/null)
    
    if [[ -z "$issue_title" || -z "$issue_identifier" ]]; then
        print_error "Invalid issue data received"
        echo "Issue data: $issue_data"
        exit 1
    fi
    
    print_success "Found issue: $issue_title"
    
    # Create and send prompt to Claude
    local prompt=$(create_claude_prompt "$issue_data")
    prompt_claude "$prompt"
    
    echo ""
    print_success "Task prompt completed!"
    echo "💡 Claude has been provided with your task details and is ready to help."
}

# Run main function with all arguments
main "$@"