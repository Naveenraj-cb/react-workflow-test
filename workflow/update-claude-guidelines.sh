#!/bin/bash

# Update CLAUDE Guidelines Script
# This script updates CLAUDE.md with learned patterns from session analysis

set -e

# Load common utilities
source "$(dirname "$0")/common-utils.sh"

# Function to show help
show_help() {
    cat << 'EOF'
📝 Update CLAUDE Guidelines
==========================

USAGE:
    ./update-claude-guidelines.sh [OPTIONS]

OPTIONS:
    --dry-run            Preview changes without applying them
    --force              Apply updates without confirmation
    --min-sessions N     Minimum sessions required for updates (default: 5)
    --backup             Create backup of current CLAUDE.md
    -h, --help          Show this help message

EXAMPLES:
    # Preview what changes would be made
    ./update-claude-guidelines.sh --dry-run

    # Apply updates with backup
    ./update-claude-guidelines.sh --backup

    # Force update without confirmation
    ./update-claude-guidelines.sh --force --min-sessions 3

This script analyzes stored session patterns and updates CLAUDE.md with:
1. Successful prompt patterns
2. Context-specific guidelines
3. Issue type best practices
4. Template improvements
5. Performance optimization tips
EOF
}

# Function to find CLAUDE.md file
find_claude_md() {
    # Check workflow directory first
    if [[ -f "workflow/CLAUDE.md" ]]; then
        echo "workflow/CLAUDE.md"
    # Check root directory
    elif [[ -f "CLAUDE.md" ]]; then
        echo "CLAUDE.md"
    # Check parent directory
    elif [[ -f "../CLAUDE.md" ]]; then
        echo "../CLAUDE.md"
    else
        echo ""
    fi
}

# Function to backup CLAUDE.md
backup_claude_md() {
    local claude_file="$1"
    local backup_file="${claude_file}.backup.$(date +%Y%m%d_%H%M%S)"
    
    cp "$claude_file" "$backup_file"
    print_success "Backup created: $backup_file"
}

# Function to generate pattern-based guidelines
generate_pattern_guidelines() {
    local data_dir=$(get_data_dir)
    local sessions_dir="$data_dir/sessions"
    
    if [[ ! -d "$sessions_dir" ]]; then
        echo ""
        return
    fi
    
    local total_sessions=$(find "$sessions_dir" -name "*.json" | wc -l)
    if [[ $total_sessions -eq 0 ]]; then
        echo ""
        return
    fi
    
    # Analyze successful patterns
    local successful_issue_types=()
    local successful_templates=()
    local successful_contexts=()
    
    for session_file in "$sessions_dir"/*.json; do
        if [[ -f "$session_file" ]]; then
            local success_rate=$(jq -r '.response_quality.success_rate // 0' "$session_file")
            local satisfaction=$(jq -r '.response_quality.user_satisfaction // 0' "$session_file")
            
            # Consider successful if success_rate > 0.7 and satisfaction >= 4
            if (( $(echo "$success_rate > 0.7" | bc -l) )) && (( $(echo "$satisfaction >= 4" | bc -l) )); then
                local issue_type=$(jq -r '.issue_type' "$session_file")
                local template=$(jq -r '.prompt.template_used' "$session_file")
                local tech_stack=$(jq -r '.project_context.tech_stack[]?' "$session_file" 2>/dev/null)
                
                successful_issue_types+=("$issue_type")
                successful_templates+=("$template")
                
                if [[ -n "$tech_stack" ]]; then
                    while IFS= read -r tech; do
                        if [[ -n "$tech" && "$tech" != "null" ]]; then
                            successful_contexts+=("$tech")
                        fi
                    done <<< "$tech_stack"
                fi
            fi
        fi
    done
    
    # Generate guidelines based on patterns
    cat << EOF

## AI Performance Guidelines (Auto-Generated)

### Generated from $total_sessions session(s) on $(date +%Y-%m-%d)

#### Most Successful Patterns
$(printf '%s\n' "${successful_issue_types[@]}" | sort | uniq -c | sort -nr | head -3 | while read count type; do
    echo "- **$type** issues: $count successful sessions"
done)

#### Effective Templates
$(printf '%s\n' "${successful_templates[@]}" | sort | uniq -c | sort -nr | head -2 | while read count template; do
    echo "- **$template**: $count successful uses"
done)

#### Context-Specific Guidelines
$(printf '%s\n' "${successful_contexts[@]}" | sort | uniq -c | sort -nr | head -3 | while read count context; do
    case "$context" in
        "react")
            echo "- **React Projects**: Include component analysis and state management considerations"
            ;;
        "typescript")
            echo "- **TypeScript Projects**: Emphasize type safety and interface definitions"
            ;;
        "jest")
            echo "- **Jest Testing**: Always include test coverage and assertion strategies"
            ;;
        "nextjs")
            echo "- **Next.js Projects**: Consider SSR/SSG implications and routing"
            ;;
        *)
            echo "- **$context**: $count successful sessions"
            ;;
    esac
done)

#### Recommended Prompt Structure
Based on successful patterns:
1. **Start with clear context**: Include issue ID, type, and current branch
2. **Be specific about deliverables**: List exactly what files/changes are needed
3. **Include project context**: Mention tech stack and existing patterns
4. **Request step-by-step approach**: Ask for implementation plan
5. **Specify testing requirements**: Include test coverage expectations

#### Performance Optimization Tips
- Break complex tasks into smaller, focused requests
- Include relevant code snippets for context
- Specify coding standards and conventions upfront
- Request documentation alongside implementation
- Ask for error handling and edge case considerations

*Note: These guidelines are automatically updated based on session performance data.*
EOF
}

# Function to check if guidelines section exists
has_performance_guidelines() {
    local claude_file="$1"
    grep -q "## AI Performance Guidelines" "$claude_file" 2>/dev/null
}

# Function to update CLAUDE.md with patterns
update_claude_md() {
    local claude_file="$1"
    local dry_run="$2"
    local force="$3"
    
    if [[ ! -f "$claude_file" ]]; then
        print_error "CLAUDE.md not found at: $claude_file"
        return 1
    fi
    
    # Generate new guidelines
    local new_guidelines=$(generate_pattern_guidelines)
    
    if [[ -z "$new_guidelines" ]]; then
        print_warning "No session data available for generating guidelines"
        return 1
    fi
    
    if [[ "$dry_run" == true ]]; then
        echo "📝 Preview of changes to $claude_file:"
        echo "======================================"
        if has_performance_guidelines "$claude_file"; then
            echo "🔄 Would update existing AI Performance Guidelines section"
        else
            echo "➕ Would add new AI Performance Guidelines section"
        fi
        echo ""
        echo "New content:"
        echo "$new_guidelines"
        return 0
    fi
    
    # Confirm changes unless forced
    if [[ "$force" != true ]]; then
        echo "📝 About to update $claude_file with learned patterns"
        if has_performance_guidelines "$claude_file"; then
            echo "🔄 This will update the existing AI Performance Guidelines section"
        else
            echo "➕ This will add a new AI Performance Guidelines section"
        fi
        echo ""
        read -p "Continue? (y/N): " confirm
        if [[ "$confirm" != "y" && "$confirm" != "Y" ]]; then
            print_status "Update cancelled by user"
            return 0
        fi
    fi
    
    # Create temporary file for updates
    local temp_file=$(mktemp)
    
    if has_performance_guidelines "$claude_file"; then
        # Update existing guidelines section
        awk '
        /^## AI Performance Guidelines/ {
            in_section = 1
            print
            while ((getline line < "'"<(echo "$new_guidelines")"'") > 0) {
                print line
            }
            next
        }
        in_section && /^## / {
            in_section = 0
        }
        !in_section {
            print
        }' "$claude_file" > "$temp_file"
    else
        # Append new guidelines section
        cp "$claude_file" "$temp_file"
        echo "$new_guidelines" >> "$temp_file"
    fi
    
    # Apply changes
    mv "$temp_file" "$claude_file"
    
    print_success "CLAUDE.md updated successfully!"
    echo "📊 Guidelines updated with patterns from session analysis"
}

# Main function
main() {
    local dry_run=false
    local force=false
    local min_sessions=5
    local backup=false
    
    # Parse command line arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            --dry-run)
                dry_run=true
                shift
                ;;
            --force)
                force=true
                shift
                ;;
            --min-sessions)
                min_sessions="$2"
                shift 2
                ;;
            --backup)
                backup=true
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
    
    echo "📝 Update CLAUDE Guidelines"
    echo "=========================="
    echo ""
    
    # Find CLAUDE.md file
    local claude_file=$(find_claude_md)
    if [[ -z "$claude_file" ]]; then
        print_error "CLAUDE.md not found in current directory, workflow/, or parent directory"
        echo "Please create a CLAUDE.md file or run this script from the project root"
        exit 1
    fi
    
    print_status "Found CLAUDE.md at: $claude_file"
    
    # Check minimum sessions requirement
    local data_dir=$(get_data_dir)
    local sessions_dir="$data_dir/sessions"
    local total_sessions=0
    
    if [[ -d "$sessions_dir" ]]; then
        total_sessions=$(find "$sessions_dir" -name "*.json" | wc -l)
    fi
    
    if [[ $total_sessions -lt $min_sessions ]]; then
        print_warning "Only $total_sessions sessions found. Need at least $min_sessions for meaningful updates."
        if [[ "$force" != true ]]; then
            echo "Use --force to override this requirement"
            exit 1
        fi
    fi
    
    print_status "Analyzing $total_sessions session(s) for pattern extraction..."
    
    # Backup if requested
    if [[ "$backup" == true ]]; then
        backup_claude_md "$claude_file"
    fi
    
    # Update CLAUDE.md
    update_claude_md "$claude_file" "$dry_run" "$force"
    
    echo ""
    print_success "CLAUDE guidelines update completed!"
    
    if [[ "$dry_run" != true ]]; then
        echo "💡 Run './analyze-patterns.sh --report' to see detailed analysis"
    fi
}

# Run main function with all arguments
main "$@"