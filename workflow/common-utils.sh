#!/bin/bash

# Common Utilities for Workflow Scripts
# This file contains shared functions and variables used across all workflow scripts

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

# Function to load environment variables from .env.local
load_env() {
    if [[ -f "$(dirname "$0")/.env.local" ]]; then
        source "$(dirname "$0")/.env.local"
        return 0
    else
        return 1
    fi
}

# Function to check if required tools are installed
check_tool() {
    local tool="$1"
    local install_msg="$2"
    
    if ! command -v "$tool" &> /dev/null; then
        print_error "$tool is required but not installed"
        if [[ -n "$install_msg" ]]; then
            echo "$install_msg"
        fi
        return 1
    fi
    return 0
}

# Function to check basic prerequisites (git, curl, jq)
check_basic_prerequisites() {
    print_status "Checking basic prerequisites..."
    
    local failed=false
    
    if ! check_tool "git"; then
        failed=true
    fi
    
    if ! check_tool "curl"; then
        failed=true
    fi
    
    if ! check_tool "jq" "  macOS: brew install jq
  Ubuntu: sudo apt-get install jq
  Windows: Download from https://stedolan.github.io/jq/"; then
        failed=true
    fi
    
    if [[ "$failed" == true ]]; then
        exit 1
    fi
    
    print_success "Basic prerequisites are installed"
}

# Function to validate JSON response
validate_json_response() {
    local response="$1"
    
    if ! echo "$response" | jq . > /dev/null 2>&1; then
        print_error "Invalid JSON response from API"
        echo "Response: $response"
        return 1
    fi
    
    return 0
}

# Function to check for API errors in response
check_api_errors() {
    local response="$1"
    local api_name="$2"
    
    if echo "$response" | jq -e '.errors' > /dev/null; then
        print_error "API error from $api_name: $(echo "$response" | jq -r '.errors[0].message')"
        return 1
    fi
    
    return 0
}

# Function to validate environment variable
validate_env_var() {
    local var_name="$1"
    local var_value="$2"
    local help_msg="$3"
    
    if [[ -z "$var_value" || "$var_value" == "your_${var_name,,}_here" ]]; then
        print_error "$var_name not set. Please set it in .env.local file."
        if [[ -n "$help_msg" ]]; then
            echo "$help_msg"
        fi
        return 1
    fi
    
    return 0
}

# Function to make Linear API call
call_linear_api() {
    local query="$1"
    
    if [[ -z "$LINEAR_API_TOKEN" ]]; then
        print_error "LINEAR_API_TOKEN not set"
        return 1
    fi
    
    local response=$(curl -s -X POST \
        -H "Authorization: $LINEAR_API_TOKEN" \
        -H "Content-Type: application/json" \
        -d "$query" \
        "https://api.linear.app/graphql")
    
    if ! validate_json_response "$response"; then
        return 1
    fi
    
    if ! check_api_errors "$response" "Linear"; then
        return 1
    fi
    
    echo "$response"
    return 0
}

# Function to get Linear issue details
get_linear_issue() {
    local issue_id="$1"
    local silent_mode="${2:-false}"
    
    if [[ "$silent_mode" == false ]]; then
        print_status "Fetching Linear issue: $issue_id" >&2
    fi
    
    local query='{
        "query": "query GetIssue($id: String!) { issue(id: $id) { id identifier title description state { name id } team { key } labels { nodes { name } } } }",
        "variables": { "id": "'$issue_id'" }
    }'
    
    local response=$(call_linear_api "$query")
    if [[ $? -ne 0 ]]; then
        echo "null"
        return 1
    fi
    
    echo "$response" | jq -r '.data.issue'
    return 0
}

# Function to create Linear comment
create_linear_comment() {
    local issue_id="$1"
    local comment_body="$2"
    local silent_mode="${3:-false}"
    
    if [[ "$silent_mode" == false ]]; then
        print_status "Creating Linear comment..." >&2
    fi
    
    local mutation='{
        "query": "mutation CreateComment($input: CommentCreateInput!) { commentCreate(input: $input) { success comment { id } } }",
        "variables": {
            "input": {
                "issueId": "'$issue_id'",
                "body": "'$comment_body'"
            }
        }
    }'
    
    local response=$(call_linear_api "$mutation")
    if [[ $? -ne 0 ]]; then
        return 1
    fi
    
    local success=$(echo "$response" | jq -r '.data.commentCreate.success')
    local comment_id=$(echo "$response" | jq -r '.data.commentCreate.comment.id // empty')
    
    if [[ "$success" == "true" && -n "$comment_id" ]]; then
        if [[ "$silent_mode" == false ]]; then
            print_success "Comment created successfully (ID: $comment_id)" >&2
        fi
        echo "$comment_id"
        return 0
    else
        if [[ "$silent_mode" == false ]]; then
            print_error "Failed to create comment - success: $success" >&2
        fi
        return 1
    fi
}

# Function to create Linear attachment
create_linear_attachment() {
    local issue_id="$1"
    local title="$2"
    local subtitle="$3"
    local url="$4"
    local icon_url="$5"
    local silent_mode="${6:-false}"
    
    if [[ "$silent_mode" == false ]]; then
        print_status "Creating Linear attachment..." >&2
    fi
    
    local mutation='{
        "query": "mutation CreateAttachment($input: AttachmentCreateInput!) { attachmentCreate(input: $input) { success attachment { id } } }",
        "variables": {
            "input": {
                "issueId": "'$issue_id'",
                "title": "'$title'",
                "subtitle": "'$subtitle'",
                "url": "'$url'",
                "iconUrl": "'$icon_url'"
            }
        }
    }'
    
    local response=$(call_linear_api "$mutation")
    if [[ $? -ne 0 ]]; then
        return 1
    fi
    
    local success=$(echo "$response" | jq -r '.data.attachmentCreate.success')
    local attachment_id=$(echo "$response" | jq -r '.data.attachmentCreate.attachment.id // empty')
    
    if [[ "$success" == "true" && -n "$attachment_id" ]]; then
        if [[ "$silent_mode" == false ]]; then
            print_success "Attachment created successfully (ID: $attachment_id)" >&2
        fi
        echo "$attachment_id"
        return 0
    else
        if [[ "$silent_mode" == false ]]; then
            print_error "Failed to create attachment - success: $success" >&2
        fi
        return 1
    fi
}

# Function to get current date in consistent format
get_current_date() {
    date +"%d/%m/%Y %I:%M %p"
}

# Function to get current git branch
get_current_branch() {
    git branch --show-current 2>/dev/null || echo "unknown"
}

# Function to extract Linear issue ID from branch name
extract_issue_id_from_branch() {
    local branch_name="$1"
    
    if [[ "$branch_name" =~ ([A-Z]+-[0-9]+) ]]; then
        echo "${BASH_REMATCH[1]}"
    else
        echo ""
    fi
}

# Function to show help message with common options
show_common_help() {
    local script_name="$1"
    local specific_help="$2"
    
    echo "Usage: $script_name [OPTIONS]"
    echo ""
    echo "Common Options:"
    echo "  -h, --help              Show this help message"
    echo ""
    echo "Environment variables:"
    echo "  LINEAR_API_TOKEN        Your Linear API token"
    echo "  GITHUB_TOKEN            Your GitHub personal access token (if needed)"
    echo "  GITHUB_REPO             GitHub repository (format: owner/repo)"
    echo ""
    
    if [[ -n "$specific_help" ]]; then
        echo "$specific_help"
        echo ""
    fi
}

# Function to parse common arguments
parse_common_args() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            -h|--help)
                return 2  # Special return code for help
                ;;
            *)
                # Return all remaining arguments
                echo "$@"
                return 0
                ;;
        esac
    done
}