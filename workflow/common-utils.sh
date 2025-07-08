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
    
    if [[ -z "$var_value" || "$var_value" == "your_$(echo "$var_name" | tr '[:upper:]' '[:lower:]')_here" ]]; then
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

# ==============================================================================
# PROMPT STORAGE & PATTERN ANALYSIS FUNCTIONS
# ==============================================================================

# Function to generate session ID
generate_session_id() {
    # Generate a UUID-like string using date and random
    echo "$(date +%Y%m%d_%H%M%S)_$(shuf -i 1000-9999 -n 1)"
}

# Function to get data directory path
get_data_dir() {
    echo "$(dirname "$0")/data"
}

# Function to ensure data directory exists
ensure_data_dir() {
    local data_dir=$(get_data_dir)
    mkdir -p "$data_dir"/{sessions,patterns,templates,analytics,training}
}

# Function to get current tech stack from package.json and other files
get_tech_stack() {
    local tech_stack=()
    
    # Check for package.json
    if [[ -f "package.json" ]]; then
        if grep -q "react" package.json; then
            tech_stack+=("react")
        fi
        if grep -q "typescript" package.json; then
            tech_stack+=("typescript")
        fi
        if grep -q "jest" package.json; then
            tech_stack+=("jest")
        fi
        if grep -q "next" package.json; then
            tech_stack+=("nextjs")
        fi
        if grep -q "express" package.json; then
            tech_stack+=("express")
        fi
    fi
    
    # Check for other tech indicators
    if [[ -f "tsconfig.json" ]]; then
        tech_stack+=("typescript")
    fi
    if [[ -f "tailwind.config.js" ]]; then
        tech_stack+=("tailwind")
    fi
    
    # Remove duplicates and join with commas
    printf '%s\n' "${tech_stack[@]}" | sort -u | tr '\n' ',' | sed 's/,$//'
}

# Function to get project context
get_project_context() {
    local current_branch=$(get_current_branch)
    local tech_stack=$(get_tech_stack)
    
    # Get recent file changes
    local files_changed=()
    if git diff --name-only HEAD~1 HEAD > /dev/null 2>&1; then
        while IFS= read -r file; do
            files_changed+=("$file")
        done < <(git diff --name-only HEAD~1 HEAD | head -10)
    fi
    
    # Convert array to JSON array
    local files_json=$(printf '%s\n' "${files_changed[@]}" | jq -R . | jq -s .)
    
    jq -n \
        --arg branch "$current_branch" \
        --arg tech_stack "$tech_stack" \
        --argjson files_changed "$files_json" \
        '{
            branch: $branch,
            tech_stack: ($tech_stack | split(",") | map(select(. != ""))),
            files_changed: $files_changed,
            timestamp: now | strftime("%Y-%m-%dT%H:%M:%SZ")
        }'
}

# Function to store session data
store_session_data() {
    local session_id="$1"
    local issue_id="$2"
    local issue_type="$3"
    local prompt="$4"
    local template_used="$5"
    local project_context="$6"
    
    ensure_data_dir
    
    local data_dir=$(get_data_dir)
    local session_file="$data_dir/sessions/${session_id}.json"
    
    # Create session data JSON
    jq -n \
        --arg session_id "$session_id" \
        --arg issue_id "$issue_id" \
        --arg issue_type "$issue_type" \
        --arg prompt "$prompt" \
        --arg template_used "$template_used" \
        --argjson project_context "$project_context" \
        '{
            timestamp: now | strftime("%Y-%m-%dT%H:%M:%SZ"),
            session_id: $session_id,
            issue_id: $issue_id,
            issue_type: $issue_type,
            project_context: $project_context,
            prompt: {
                original: $prompt,
                modifications: null,
                template_used: $template_used
            },
            response_quality: {
                success_rate: null,
                time_to_completion: null,
                user_satisfaction: null,
                follow_up_needed: null
            },
            patterns_identified: [],
            outcome: {
                task_completed: null,
                files_modified: null,
                tests_passed: null,
                commit_successful: null
            },
            status: "initiated"
        }' > "$session_file"
    
    echo "$session_id"
}

# Function to update session outcome
update_session_outcome() {
    local session_id="$1"
    local success_rate="$2"
    local user_satisfaction="$3"
    local task_completed="$4"
    local files_modified="$5"
    
    ensure_data_dir
    
    local data_dir=$(get_data_dir)
    local session_file="$data_dir/sessions/${session_id}.json"
    
    if [[ -f "$session_file" ]]; then
        # Update the session file with outcome data
        jq --arg success_rate "$success_rate" \
           --arg user_satisfaction "$user_satisfaction" \
           --arg task_completed "$task_completed" \
           --arg files_modified "$files_modified" \
           '.response_quality.success_rate = ($success_rate | tonumber) |
            .response_quality.user_satisfaction = ($user_satisfaction | tonumber) |
            .outcome.task_completed = ($task_completed == "true") |
            .outcome.files_modified = ($files_modified | tonumber) |
            .status = "completed"' \
           "$session_file" > "$session_file.tmp" && mv "$session_file.tmp" "$session_file"
    fi
}

# Function to analyze patterns from sessions
analyze_session_patterns() {
    local data_dir=$(get_data_dir)
    local sessions_dir="$data_dir/sessions"
    local patterns_file="$data_dir/patterns/successful_patterns.json"
    
    if [[ ! -d "$sessions_dir" ]]; then
        return 0
    fi
    
    local total_sessions=0
    local successful_sessions=0
    local total_satisfaction=0
    local successful_patterns=()
    
    # Analyze all session files
    for session_file in "$sessions_dir"/*.json; do
        if [[ -f "$session_file" ]]; then
            total_sessions=$((total_sessions + 1))
            
            local success_rate=$(jq -r '.response_quality.success_rate // 0' "$session_file")
            local satisfaction=$(jq -r '.response_quality.user_satisfaction // 0' "$session_file")
            
            # Consider successful if success_rate > 0.7 and satisfaction > 3.5
            if (( $(echo "$success_rate > 0.7" | bc -l) )) && (( $(echo "$satisfaction > 3.5" | bc -l) )); then
                successful_sessions=$((successful_sessions + 1))
                
                # Extract patterns from successful sessions
                local issue_type=$(jq -r '.issue_type' "$session_file")
                local template_used=$(jq -r '.prompt.template_used' "$session_file")
                successful_patterns+=("$issue_type:$template_used")
            fi
            
            total_satisfaction=$(echo "$total_satisfaction + $satisfaction" | bc -l)
        fi
    done
    
    # Update patterns file
    if [[ $total_sessions -gt 0 ]]; then
        local avg_satisfaction=$(echo "scale=2; $total_satisfaction / $total_sessions" | bc -l)
        local success_rate=$(echo "scale=2; $successful_sessions / $total_sessions" | bc -l)
        
        jq --arg total_sessions "$total_sessions" \
           --arg avg_satisfaction "$avg_satisfaction" \
           --arg success_rate "$success_rate" \
           '.metadata.total_sessions_analyzed = ($total_sessions | tonumber) |
            .metadata.last_updated = now | strftime("%Y-%m-%dT%H:%M:%SZ") |
            .performance_metrics.average_success_rate = ($success_rate | tonumber) |
            .performance_metrics.average_user_satisfaction = ($avg_satisfaction | tonumber)' \
           "$patterns_file" > "$patterns_file.tmp" && mv "$patterns_file.tmp" "$patterns_file"
    fi
}

# Function to get session feedback
get_session_feedback() {
    local session_id="$1"
    
    echo ""
    echo "📊 Session Feedback (Session ID: $session_id)"
    echo "=============================================="
    echo ""
    
    # Get user satisfaction rating
    echo "How satisfied are you with Claude's performance? (1-5 scale)"
    echo "1 = Very Poor, 2 = Poor, 3 = Average, 4 = Good, 5 = Excellent"
    read -p "Rating: " satisfaction
    
    # Validate input
    if ! [[ "$satisfaction" =~ ^[1-5]$ ]]; then
        satisfaction="3"
        echo "Invalid input, defaulting to 3 (Average)"
    fi
    
    # Get task completion status
    echo ""
    echo "Was the task completed successfully? (y/n)"
    read -p "Completed: " completed
    
    case "$completed" in
        y|Y|yes|Yes)
            completed="true"
            ;;
        *)
            completed="false"
            ;;
    esac
    
    # Get number of files modified (approximate)
    echo ""
    echo "Approximately how many files were modified/created? (number)"
    read -p "Files modified: " files_modified
    
    # Validate number
    if ! [[ "$files_modified" =~ ^[0-9]+$ ]]; then
        files_modified="0"
    fi
    
    # Calculate success rate based on completion and satisfaction
    local success_rate
    if [[ "$completed" == "true" && "$satisfaction" -ge 4 ]]; then
        success_rate="0.9"
    elif [[ "$completed" == "true" && "$satisfaction" -ge 3 ]]; then
        success_rate="0.7"
    elif [[ "$completed" == "true" ]]; then
        success_rate="0.5"
    else
        success_rate="0.2"
    fi
    
    # Update session with feedback
    update_session_outcome "$session_id" "$success_rate" "$satisfaction" "$completed" "$files_modified"
    
    # Analyze patterns after each session
    analyze_session_patterns
    
    echo ""
    print_success "Thank you for your feedback! This helps improve future prompts."
    echo ""
}