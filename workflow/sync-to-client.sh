#!/bin/bash

# Sync to Client Script
# This script syncs changes from private repo to client repo without commit history

set -e

# Load common utilities
source "$(dirname "$0")/common-utils.sh"

# Load environment variables
load_env

# Default exclusion patterns
DEFAULT_EXCLUSIONS=(
    "workflow/"
    ".env.local"
    ".env.local.example"
    "CLAUDE.md"
    ".git/"
    "node_modules/"
    ".DS_Store"
    "*.log"
)

# Function to show help
show_help() {
    cat << 'EOF'
🔄 Sync to Client Tool
======================

USAGE:
    ./sync-to-client.sh [OPTIONS]

SYNC MODES:
    Default              Sync current branch vs base branch
    -r, --range RANGE    Sync specific commit range (e.g., "abc123..def456")
    -c, --commit HASH    Sync single commit
    --last N             Sync last N commits
    --since DATE         Sync commits since date (e.g., "yesterday", "2024-01-15")

OPTIONS:
    -b, --base-branch    Override base branch detection
    --client-path PATH   Override client repo path
    --exclude PATTERN    Additional exclusion pattern
    --dry-run           Preview changes without copying
    -h, --help          Show this help message

ENVIRONMENT VARIABLES:
    CLIENT_REPO_PATH    Path to client repository (required)

EXAMPLES:
    # Sync current branch
    ./sync-to-client.sh

    # Sync specific commit range
    ./sync-to-client.sh -r "abc123..def456"

    # Sync single commit
    ./sync-to-client.sh -c "abc123"

    # Sync last 5 commits
    ./sync-to-client.sh --last 5

    # Sync with custom base branch
    ./sync-to-client.sh -b develop

    # Dry run with preview
    ./sync-to-client.sh --dry-run
EOF
}

# Function to validate repositories
validate_repos() {
    print_status "Validating repositories..."
    
    # Check if we're in a git repository
    if ! git rev-parse --git-dir > /dev/null 2>&1; then
        print_error "Current directory is not a git repository"
        exit 1
    fi
    
    # Check if CLIENT_REPO_PATH is set
    if [[ -z "$CLIENT_REPO_PATH" ]]; then
        print_error "CLIENT_REPO_PATH not set in .env.local"
        echo "Please set CLIENT_REPO_PATH=/path/to/client/repo in .env.local"
        exit 1
    fi
    
    # Check if client repo exists and is a git repo
    if [[ ! -d "$CLIENT_REPO_PATH" ]]; then
        print_error "Client repository not found: $CLIENT_REPO_PATH"
        exit 1
    fi
    
    if ! git -C "$CLIENT_REPO_PATH" rev-parse --git-dir > /dev/null 2>&1; then
        print_error "Client path is not a git repository: $CLIENT_REPO_PATH"
        exit 1
    fi
    
    print_success "Repositories validated"
}

# Function to check working directory state
check_working_state() {
    print_status "Checking working directory state..."
    
    # Check if working directory is clean
    if ! git diff-index --quiet HEAD --; then
        print_warning "Working directory has uncommitted changes"
        echo "Please commit or stash changes before syncing"
        read -p "Continue anyway? (y/N): " continue_dirty
        if [[ "$continue_dirty" != "y" && "$continue_dirty" != "Y" ]]; then
            exit 1
        fi
    fi
    
    print_success "Working directory state checked"
}

# Function to detect base branch
detect_base_branch() {
    print_status "Detecting base branch..." >&2
    
    # Method 1: Try merge-base with common branches
    local common_branches=("main" "master" "develop" "staging")
    for branch in "${common_branches[@]}"; do
        if git show-ref --verify --quiet "refs/heads/$branch"; then
            local merge_base=$(git merge-base "$branch" HEAD 2>/dev/null)
            if [[ -n "$merge_base" ]]; then
                local base_commit=$(git rev-parse "$branch")
                if [[ "$merge_base" == "$base_commit" ]] || git merge-base --is-ancestor "$branch" HEAD 2>/dev/null; then
                    echo "$branch"
                    return 0
                fi
            fi
        fi
    done
    
    # Method 2: Check reflog for branch creation
    local created_from=$(git reflog --oneline | grep -E "checkout: moving from" | head -1 | awk '{print $6}' | sed 's/.*\///')
    if [[ -n "$created_from" && "$created_from" != "HEAD" ]]; then
        echo "$created_from"
        return 0
    fi
    
    # Method 3: Default fallback
    echo "main"
}

# Function to get base branch with user confirmation
get_base_branch() {
    local base_branch="$1"
    
    # If base branch not provided, detect it
    if [[ -z "$base_branch" ]]; then
        base_branch=$(detect_base_branch)
    fi
    
    # Prompt user for confirmation
    echo "📋 Detected base branch: $base_branch" >&2
    read -p "❓ Is this correct? (y/n/enter different): " confirmation
    
    case $confirmation in
        y|Y|"")
            # Use detected/provided branch
            ;;
        n|N)
            read -p "Enter correct base branch: " base_branch
            ;;
        *)
            # User entered a different branch name
            base_branch="$confirmation"
            ;;
    esac
    
    # Validate base branch exists
    if ! git show-ref --verify --quiet "refs/heads/$base_branch"; then
        print_error "Base branch '$base_branch' does not exist"
        exit 1
    fi
    
    echo "$base_branch"
}

# Function to get file changes based on sync mode
get_file_changes() {
    local mode="$1"
    local param="$2"
    local base_branch="$3"
    
    case $mode in
        "current")
            git diff --name-only "$base_branch..HEAD"
            ;;
        "range")
            git diff --name-only "$param"
            ;;
        "commit")
            git show --name-only --pretty=format: "$param" | grep -v '^$'
            ;;
        "last")
            git diff --name-only "HEAD~$param..HEAD"
            ;;
        "since")
            git diff --name-only --since="$param" "$base_branch..HEAD"
            ;;
        *)
            print_error "Unknown sync mode: $mode"
            exit 1
            ;;
    esac
}

# Function to filter excluded files
filter_files() {
    local files=("$@")
    local filtered_files=()
    
    for file in "${files[@]}"; do
        local exclude=false
        
        # Check against exclusion patterns
        for pattern in "${ALL_EXCLUSIONS[@]}"; do
            if [[ "$file" == $pattern* ]] || [[ "$file" == *"$pattern"* ]]; then
                exclude=true
                break
            fi
        done
        
        if [[ "$exclude" == false ]]; then
            filtered_files+=("$file")
        fi
    done
    
    printf '%s\n' "${filtered_files[@]}"
}

# Function to preview changes
preview_changes() {
    local files=("$@")
    
    if [[ ${#files[@]} -eq 0 ]]; then
        print_warning "No files to sync"
        return 1
    fi
    
    echo ""
    echo "📋 Files to sync (${#files[@]} total):"
    echo "================================"
    
    for file in "${files[@]}"; do
        if [[ -f "$file" ]]; then
            echo "  📄 $file"
        elif [[ ! -e "$file" ]]; then
            echo "  🗑️  $file (deleted)"
        else
            echo "  📁 $file"
        fi
    done
    
    echo ""
    echo "🎯 Target: $CLIENT_REPO_PATH"
    echo ""
    
    return 0
}

# Function to copy files to client repo
copy_files() {
    local files=("$@")
    local copied_count=0
    local deleted_count=0
    
    print_status "Copying files to client repository..."
    
    for file in "${files[@]}"; do
        local client_file="$CLIENT_REPO_PATH/$file"
        local client_dir=$(dirname "$client_file")
        
        if [[ -f "$file" ]]; then
            # Create directory if it doesn't exist
            mkdir -p "$client_dir"
            
            # Copy file
            cp "$file" "$client_file"
            ((copied_count++))
            
        elif [[ ! -e "$file" ]]; then
            # File was deleted, remove from client repo if it exists
            if [[ -f "$client_file" ]]; then
                rm "$client_file"
                ((deleted_count++))
                
                # Remove empty directories
                rmdir "$client_dir" 2>/dev/null || true
            fi
        fi
    done
    
    echo ""
    print_success "Sync completed!"
    echo "  📄 Copied: $copied_count files"
    if [[ $deleted_count -gt 0 ]]; then
        echo "  🗑️  Deleted: $deleted_count files"
    fi
    echo ""
    
    print_status "📝 Next steps:"
    echo "  1. cd $CLIENT_REPO_PATH"
    echo "  2. Review changes: git status && git diff"
    echo "  3. Commit changes: git add . && git commit -m 'Your commit message'"
}

# Main function
main() {
    echo "🔄 Sync to Client Tool"
    echo "======================"
    
    # Parse command line arguments
    local sync_mode="current"
    local sync_param=""
    local base_branch=""
    local client_path_override=""
    local additional_exclusions=()
    local dry_run=false
    
    while [[ $# -gt 0 ]]; do
        case $1 in
            -r|--range)
                sync_mode="range"
                sync_param="$2"
                shift 2
                ;;
            -c|--commit)
                sync_mode="commit"
                sync_param="$2"
                shift 2
                ;;
            --last)
                sync_mode="last"
                sync_param="$2"
                shift 2
                ;;
            --since)
                sync_mode="since"
                sync_param="$2"
                shift 2
                ;;
            -b|--base-branch)
                base_branch="$2"
                shift 2
                ;;
            --client-path)
                client_path_override="$2"
                shift 2
                ;;
            --exclude)
                additional_exclusions+=("$2")
                shift 2
                ;;
            --dry-run)
                dry_run=true
                shift
                ;;
            -h|--help)
                show_help
                exit 0
                ;;
            *)
                print_error "Unknown option: $1"
                echo "Use -h or --help for usage information"
                exit 1
                ;;
        esac
    done
    
    # Override client path if provided
    if [[ -n "$client_path_override" ]]; then
        CLIENT_REPO_PATH="$client_path_override"
    fi
    
    # Combine exclusions
    ALL_EXCLUSIONS=("${DEFAULT_EXCLUSIONS[@]}" "${additional_exclusions[@]}")
    
    # Validate repositories
    validate_repos
    
    # Check working state
    check_working_state
    
    # Get base branch for current mode (not needed for commit/range modes)
    if [[ "$sync_mode" == "current" || "$sync_mode" == "since" ]]; then
        base_branch=$(get_base_branch "$base_branch")
        echo "✅ Using base branch: $base_branch"
    fi
    
    # Get file changes
    print_status "Analyzing changes..."
    local file_list
    file_list=$(get_file_changes "$sync_mode" "$sync_param" "$base_branch")
    
    if [[ -z "$file_list" ]]; then
        print_warning "No changes found to sync"
        exit 0
    fi
    
    # Convert to array and filter files
    local files_array=()
    while IFS= read -r line; do
        [[ -n "$line" ]] && files_array+=("$line")
    done <<< "$file_list"
    
    local filtered_files
    filtered_files=$(filter_files "${files_array[@]}")
    
    if [[ -z "$filtered_files" ]]; then
        print_warning "No files to sync after filtering"
        exit 0
    fi
    
    # Convert filtered files to array
    local final_files=()
    while IFS= read -r line; do
        [[ -n "$line" ]] && final_files+=("$line")
    done <<< "$filtered_files"
    
    # Preview changes
    if ! preview_changes "${final_files[@]}"; then
        exit 0
    fi
    
    # Confirm sync
    if [[ "$dry_run" == true ]]; then
        print_status "🔍 Dry run completed - no files were copied"
        exit 0
    fi
    
    read -p "📋 Proceed with sync? (y/N): " proceed
    if [[ "$proceed" != "y" && "$proceed" != "Y" ]]; then
        print_status "Sync cancelled"
        exit 0
    fi
    
    # Copy files
    copy_files "${final_files[@]}"
}

# Run main function with all arguments
main "$@"