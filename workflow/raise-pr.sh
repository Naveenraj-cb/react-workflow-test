#!/bin/bash

# Raise PR Script
# This script pushes current branch to origin and creates a PR to the base branch

set -e

# Load common utilities
source "$(dirname "$0")/common-utils.sh"

# Load environment variables
load_env

# Function to check if required tools are installed
check_prerequisites() {
    check_basic_prerequisites
    
    if ! check_tool "gh" "Install from: https://cli.github.com/
  macOS: brew install gh
  Ubuntu: sudo apt install gh"; then
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

# Function to get Linear issue details (using common utility)
get_linear_issue_local() {
    local issue_id="$1"
    
    if [[ -z "$LINEAR_API_TOKEN" ]]; then
        echo "null"
        return
    fi
    
    local issue_data=$(get_linear_issue "$issue_id" true)
    if [[ $? -ne 0 || "$issue_data" == "null" ]]; then
        print_warning "Failed to fetch Linear issue: $issue_id" >&2
        echo "null"
        return
    fi
    
    echo "$issue_data"
}

# Function to extract Linear issue ID from branch name (using common utility)
# This function is now provided by common-utils.sh

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
        local issue_data=$(get_linear_issue_local "$issue_id")
        
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

# Function to connect PR to Linear issue
connect_pr_to_linear() {
    local issue_id="$1"
    local pr_url="$2"
    local pr_title="$3"
    
    if [[ -z "$LINEAR_API_TOKEN" || -z "$issue_id" ]]; then
        print_warning "Cannot connect PR to Linear - missing token or issue ID"
        return 0
    fi
    
    print_status "Connecting PR to Linear issue..."
    
    # Extract PR number from URL
    local pr_number=$(echo "$pr_url" | grep -o '[0-9]\+$')
    local created_date=$(get_current_date)
    
    # Create attachment for PR
    local attachment_id=$(create_linear_attachment "$issue_id" "GitHub PR #$pr_number: '$pr_title'" "Created '$created_date'" "$pr_url" "https://github.com/favicon.ico" true)
    
    if [[ $? -eq 0 ]]; then
        print_success "PR connected to Linear issue"
        return 0
    else
        print_warning "Could not connect PR to Linear"
        return 1
    fi
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
        echo "=� Title: $pr_title"
        echo "<? Branch: $current_branch � $base_branch"
        echo "= URL: $pr_url"
        return 0
    else
        print_error "Failed to create pull request"
        exit 1
    fi
}

# Main function
main() {
    echo "=� Raise PR Tool"
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
    local current_branch=$(get_current_branch)
    
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
    local pr_url=$(create_pull_request "$current_branch" "$base_branch" "$pr_title" "$pr_description")
    
    # Connect PR to Linear if successful and issue_id available
    if [[ $? -eq 0 && -n "$pr_url" && -n "$issue_id" ]]; then
        connect_pr_to_linear "$issue_id" "$pr_url" "$pr_title"
    fi
    
    echo ""
    print_success "<� PR creation completed successfully!"
    
    if [[ -n "$issue_id" ]]; then
        echo ""
        print_status "=� Next steps:"
        echo "   1. Review the PR and make any necessary changes"
        echo "   2. Request reviews from team members"
        echo "   3. Merge the PR when approved"
        echo ""
        echo "🤖 Would you like to run the mark-task-complete script now? (y/n)"
        read -r complete_task_response
        
        if [[ "$complete_task_response" =~ ^[Yy]$ ]]; then
            echo ""
            print_status "Running mark-task-complete script..."
            "$(dirname "$0")/mark-task-complete.sh" -i "$issue_id"
        else
            echo ""
            print_status "Run later with: ./mark-task-complete.sh -i $issue_id"
        fi
    fi
}

# Run main function with all arguments
main "$@"