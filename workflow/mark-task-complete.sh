#!/bin/bash

# Mark Task Complete Script
# This script updates Linear task status to "Done" and adds task metrics

set -e

# Load common utilities
source "$(dirname "$0")/common-utils.sh"

# Load environment variables
load_env

# Function to check if required tools are installed
check_prerequisites() {
    check_basic_prerequisites
}

# Function to validate environment variables
check_config() {
    print_status "Checking configuration..."
    
    if ! validate_env_var "LINEAR_API_TOKEN" "$LINEAR_API_TOKEN" "Get your token from: https://linear.app/settings/api"; then
        exit 1
    fi
    
    print_success "Configuration is valid"
}

# Function to get Linear issue details
get_linear_issue() {
    local issue_id="$1"
    
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

# Function to get workflow states
get_workflow_states() {
    print_status "Fetching workflow states..." >&2
    
    local query='{
        "query": "query GetWorkflowStates { workflowStates { nodes { id name type } } }"
    }'
    
    local response=$(curl -s -X POST \
        -H "Authorization: $LINEAR_API_TOKEN" \
        -H "Content-Type: application/json" \
        -d "$query" \
        "https://api.linear.app/graphql")
    
    if ! echo "$response" | jq . > /dev/null 2>&1; then
        print_error "Invalid JSON response from Linear API"
        return 1
    fi
    
    if echo "$response" | jq -e '.errors' > /dev/null; then
        print_error "Failed to fetch workflow states: $(echo "$response" | jq -r '.errors[0].message')"
        return 1
    fi
    
    echo "$response" | jq -r '.data.workflowStates.nodes'
}

# Function to update Linear issue status to Done
update_issue_status() {
    local issue_id="$1"
    
    print_status "Updating issue status to Done..."
    
    # Get workflow states to find the "Done" state ID
    local states=$(get_workflow_states)
    if [[ -z "$states" ]]; then
        print_error "Failed to get workflow states"
        return 1
    fi
    
    local done_state_id=$(echo "$states" | jq -r '.[] | select(.name == "Done" or .type == "completed") | .id' | head -1)
    
    if [[ -z "$done_state_id" || "$done_state_id" == "null" ]]; then
        print_error "Could not find 'Done' state ID"
        echo "Available states:"
        echo "$states" | jq -r '.[] | "  - \(.name) (type: \(.type), id: \(.id))"'
        return 1
    fi
    
    local mutation='{
        "query": "mutation { issueUpdate(id: \"'$issue_id'\", input: { stateId: \"'$done_state_id'\" }) { success issue { id identifier state { name } } } }"
    }'
    
    local response=$(curl -s -X POST \
        -H "Authorization: $LINEAR_API_TOKEN" \
        -H "Content-Type: application/json" \
        -d "$mutation" \
        "https://api.linear.app/graphql")
    
    if echo "$response" | jq -e '.errors' > /dev/null; then
        print_error "Failed to update issue status: $(echo "$response" | jq -r '.errors[0].message')"
        return 1
    fi
    
    print_success "Issue status updated to Done"
}

# Function to analyze git commits in current branch
analyze_git_commits() {
    local base_branch="$1"
    
    print_status "Analyzing git commits..." >&2
    
    # Get current branch
    local current_branch=$(git branch --show-current)
    
    if [[ -z "$current_branch" ]]; then
        print_error "Could not determine current branch" >&2
        return 1
    fi
    
    # Get commits since diverging from base branch
    local commits=$(git log --oneline "$base_branch..$current_branch" 2>/dev/null || git log --oneline -10)
    
    if [[ -z "$commits" ]]; then
        print_warning "No commits found in current branch" >&2
        echo "0 0 0 0 0 0 0 0 unknown"
        return 0
    fi
    
    local total_commits=$(echo "$commits" | wc -l | tr -d ' ')
    local ai_commits=$(echo "$commits" | grep -c "\[AI\]" || echo "0")
    local dev_commits=$(echo "$commits" | grep -c "\[DEV\]" || echo "0")
    
    # Ensure numeric values
    [[ "$total_commits" =~ ^[0-9]+$ ]] || total_commits=0
    [[ "$ai_commits" =~ ^[0-9]+$ ]] || ai_commits=0
    [[ "$dev_commits" =~ ^[0-9]+$ ]] || dev_commits=0
    
    local other_commits=$((total_commits - ai_commits - dev_commits))
    
    # Calculate AI/Dev percentages
    local ai_percentage=0
    local dev_percentage=0
    
    if [[ $total_commits -gt 0 ]]; then
        ai_percentage=$((ai_commits * 100 / total_commits))
        dev_percentage=$((dev_commits * 100 / total_commits))
    fi
    
    # Get code changes (lines added/removed, files changed)
    local git_stats=$(git diff --stat "$base_branch..$current_branch" 2>/dev/null || git diff --stat HEAD~${total_commits}..HEAD 2>/dev/null || echo "")
    
    local lines_added=0
    local lines_removed=0
    local files_changed=0
    
    if [[ -n "$git_stats" ]]; then
        # Extract stats from git diff --stat output
        local stats_line=$(echo "$git_stats" | tail -1)
        if [[ "$stats_line" == *"insertion"* || "$stats_line" == *"deletion"* ]]; then
            lines_added=$(echo "$stats_line" | grep -o '[0-9]\+ insertion' | grep -o '[0-9]\+' | head -1 || echo "0")
            lines_removed=$(echo "$stats_line" | grep -o '[0-9]\+ deletion' | grep -o '[0-9]\+' | head -1 || echo "0")
            files_changed=$(echo "$stats_line" | grep -o '[0-9]\+ file' | grep -o '[0-9]\+' | head -1 || echo "0")
            
            # Ensure numeric values
            [[ "$lines_added" =~ ^[0-9]+$ ]] || lines_added=0
            [[ "$lines_removed" =~ ^[0-9]+$ ]] || lines_removed=0
            [[ "$files_changed" =~ ^[0-9]+$ ]] || files_changed=0
        fi
    fi
    
    # Get branch creation date (approximate duration)
    local first_commit_time=$(git log --format="%ct" "$base_branch..$current_branch" 2>/dev/null | tail -1)
    local branch_age="unknown"
    
    if [[ -n "$first_commit_time" && "$first_commit_time" =~ ^[0-9]+$ ]]; then
        local current_time=$(date +%s)
        local duration_seconds=$(( current_time - first_commit_time ))
        local duration_minutes=$(( duration_seconds / 60 ))
        local duration_hours=$(( duration_minutes / 60 ))
        local duration_days=$(( duration_hours / 24 ))
        
        if [[ $duration_minutes -lt 60 ]]; then
            branch_age="${duration_minutes}m"
        elif [[ $duration_hours -lt 24 ]]; then
            local remaining_minutes=$(( duration_minutes % 60 ))
            branch_age="${duration_hours}h ${remaining_minutes}m"
        elif [[ $duration_days -le 30 ]]; then
            local remaining_hours=$(( duration_hours % 24 ))
            branch_age="${duration_days}d ${remaining_hours}h"
        else
            local duration_months=$(( duration_days / 30 ))
            local remaining_days=$(( duration_days % 30 ))
            branch_age="${duration_months}mo ${remaining_days}d"
        fi
    fi
    
    # Return values: ai_percentage dev_percentage total_commits ai_commits dev_commits other_commits lines_added lines_removed files_changed branch_age
    echo "$ai_percentage $dev_percentage $total_commits $ai_commits $dev_commits $other_commits $lines_added $lines_removed $files_changed $branch_age"
}

# Function to create task metrics comment
create_metrics_comment() {
    local issue_id="$1"
    local ai_percentage="$2"
    local dev_percentage="$3"
    local total_commits="$4"
    local ai_commits="$5"
    local dev_commits="$6"
    local other_commits="$7"
    local lines_added="$8"
    local lines_removed="$9"
    local files_changed="${10}"
    local branch_age="${11}"
    
    print_status "Creating task metrics comment..." >&2
    
    local current_date=$(date +"%d/%m/%Y %I:%M %p")
    local current_branch=$(git branch --show-current)
    
    local comment_body="✅ **Task Completed** - ${current_date}\\n\\n**PR Info:** [View PR](https://github.com/${GITHUB_REPO}/pull/)\\n\\n🤖 **AI/Dev Split:** ${ai_percentage}% AI, ${dev_percentage}% Dev\\n📊 **Commits:** ${total_commits} total (${ai_commits} AI, ${dev_commits} Dev)\\n📝 **Changes:** +${lines_added}/-${lines_removed} lines, ${files_changed} files\\n⏱️ **Duration:** ${branch_age}\\n🔀 **Branch:** ${current_branch}"
    
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
        print_error "Failed to create metrics comment: $(echo "$response" | jq -r '.errors[0].message')" >&2
        return 1
    fi
    
    # Check if comment was successfully created
    local comment_success=$(echo "$response" | jq -r '.data.commentCreate.success')
    local comment_id=$(echo "$response" | jq -r '.data.commentCreate.comment.id // empty')
    
    if [[ "$comment_success" == "true" && -n "$comment_id" ]]; then
        print_success "Task metrics comment added to Linear issue (ID: $comment_id)" >&2
        return 0
    else
        print_error "Failed to create metrics comment - success: $comment_success" >&2
        return 1
    fi
}

# Main function
main() {
    echo "✅ Mark Task Complete Tool"
    echo "======================"
    
    # Parse command line arguments
    local issue_id=""
    local base_branch="main"
    local skip_status_update=false
    
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
            --skip-status-update)
                skip_status_update=true
                shift
                ;;
            -h|--help)
                echo "Usage: $0 -i ISSUE_ID [-b BASE_BRANCH] [--skip-status-update]"
                echo ""
                echo "Options:"
                echo "  -i, --issue             Linear issue ID (required)"
                echo "  -b, --base-branch       Base branch to compare against (default: main)"
                echo "  --skip-status-update    Skip updating issue status to Done"
                echo "  -h, --help              Show this help message"
                echo ""
                echo "Environment variables required:"
                echo "  LINEAR_API_TOKEN        Your Linear API token"
                echo ""
                echo "This script:"
                echo "1. Updates Linear issue status to 'Done'"
                echo "2. Analyzes git commits in current branch"
                echo "3. Posts task metrics comment to Linear issue"
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
        echo "Example: $0 -i COD-294"
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
    
    local issue_title=$(echo "$issue_data" | jq -r '.title')
    local issue_identifier=$(echo "$issue_data" | jq -r '.identifier')
    local internal_id=$(echo "$issue_data" | jq -r '.id')
    
    print_success "Found issue: $issue_title ($issue_identifier)"
    
    # Update issue status to Done (unless skipped)
    if [[ "$skip_status_update" == false ]]; then
        update_issue_status "$internal_id"
    else
        print_status "Skipping status update (--skip-status-update flag used)"
    fi
    
    # Analyze git commits
    print_status "Analyzing git commit metrics..."
    local commit_analysis=$(analyze_git_commits "$base_branch")
    
    # Parse the analysis results
    local metrics_array=($commit_analysis)
    local ai_percentage=${metrics_array[0]:-0}
    local dev_percentage=${metrics_array[1]:-0}
    local total_commits=${metrics_array[2]:-0}
    local ai_commits=${metrics_array[3]:-0}
    local dev_commits=${metrics_array[4]:-0}
    local other_commits=${metrics_array[5]:-0}
    local lines_added=${metrics_array[6]:-0}
    local lines_removed=${metrics_array[7]:-0}
    local files_changed=${metrics_array[8]:-0}
    local branch_age=${metrics_array[9]:-"unknown"}
    
    # Create metrics comment
    print_status "Posting task completion metrics..."
    if create_metrics_comment "$internal_id" "$ai_percentage" "$dev_percentage" "$total_commits" "$ai_commits" "$dev_commits" "$other_commits" "$lines_added" "$lines_removed" "$files_changed" "$branch_age"; then
        echo ""
        print_success "Task completion process finished!"
        echo "📋 Issue: $issue_title"
        echo "🔢 AI/Dev Split: ${ai_percentage}%/${dev_percentage}%"
        echo "📊 Commits: $total_commits total ($ai_commits AI, $dev_commits Dev, $other_commits Other)"
        echo "📝 Code Changes: +$lines_added/-$lines_removed lines, $files_changed files"
        echo "⏱️  Duration: $branch_age"
        echo ""
        print_success "✅ Metrics comment posted to Linear issue successfully!"
        
        echo ""
        echo "🔄 Would you like to sync changes to client repository? (y/n)"
        read -r sync_response
        
        if [[ "$sync_response" =~ ^[Yy]$ ]]; then
            echo ""
            print_status "Running sync-to-client script..."
            "$(dirname "$0")/sync-to-client.sh"
        else
            echo ""
            print_status "Run later with: ./sync-to-client.sh"
        fi
    else
        echo ""
        print_error "Task completion process had issues with metrics posting"
        echo "📋 Issue: $issue_title"
        echo "🔢 AI/Dev Split: ${ai_percentage}%/${dev_percentage}%"
        echo "📊 Commits: $total_commits total ($ai_commits AI, $dev_commits Dev, $other_commits Other)"
        echo "📝 Code Changes: +$lines_added/-$lines_removed lines, $files_changed files"
        echo "⏱️  Duration: $branch_age"
        echo ""
        print_warning "⚠️  Please check Linear issue manually for metrics comment"
        exit 1
    fi
}

# Run main function with all arguments
main "$@"