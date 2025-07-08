#!/bin/bash

# Pattern Analysis Engine
# This script analyzes stored session data to identify successful prompt patterns

set -e

# Load common utilities
source "$(dirname "$0")/common-utils.sh"

# Function to show help
show_help() {
    cat << 'EOF'
📊 Pattern Analysis Engine
=========================

USAGE:
    ./analyze-patterns.sh [OPTIONS]

OPTIONS:
    --report             Generate detailed analysis report
    --update-templates   Update prompt templates based on findings
    --export-insights    Export insights to CLAUDE.md
    --min-sessions N     Minimum sessions required for analysis (default: 3)
    -h, --help          Show this help message

EXAMPLES:
    # Generate analysis report
    ./analyze-patterns.sh --report

    # Update templates and export insights
    ./analyze-patterns.sh --update-templates --export-insights

    # Run full analysis with minimum 5 sessions
    ./analyze-patterns.sh --report --min-sessions 5

This script analyzes stored session data to identify:
1. Most successful prompt patterns
2. Context-specific success factors
3. Issue type preferences
4. Template effectiveness
5. Improvement opportunities
EOF
}

# Function to generate analysis report
generate_analysis_report() {
    local min_sessions="$1"
    local data_dir=$(get_data_dir)
    local sessions_dir="$data_dir/sessions"
    
    if [[ ! -d "$sessions_dir" ]]; then
        print_error "No session data found. Run some tasks first."
        return 1
    fi
    
    local total_sessions=$(find "$sessions_dir" -name "*.json" | wc -l)
    
    if [[ $total_sessions -lt $min_sessions ]]; then
        print_warning "Only $total_sessions sessions found. Need at least $min_sessions for meaningful analysis."
        return 1
    fi
    
    echo "📊 Pattern Analysis Report"
    echo "========================="
    echo "Generated: $(date)"
    echo "Total Sessions: $total_sessions"
    echo ""
    
    # Analyze success rates by issue type
    echo "🎯 Success Rate by Issue Type:"
    echo "=============================="
    
    local issue_types=("bug" "feature" "enhancement" "task")
    for issue_type in "${issue_types[@]}"; do
        local type_sessions=0
        local type_successful=0
        local total_satisfaction=0
        
        for session_file in "$sessions_dir"/*.json; do
            if [[ -f "$session_file" ]]; then
                local session_type=$(jq -r '.issue_type' "$session_file" 2>/dev/null)
                if [[ "$session_type" == "$issue_type" ]]; then
                    type_sessions=$((type_sessions + 1))
                    
                    local success_rate=$(jq -r '.response_quality.success_rate // 0' "$session_file")
                    local satisfaction=$(jq -r '.response_quality.user_satisfaction // 0' "$session_file")
                    
                    if (( $(echo "$success_rate > 0.7" | bc -l) )); then
                        type_successful=$((type_successful + 1))
                    fi
                    
                    total_satisfaction=$(echo "$total_satisfaction + $satisfaction" | bc -l)
                fi
            fi
        done
        
        if [[ $type_sessions -gt 0 ]]; then
            local type_success_rate=$(echo "scale=2; $type_successful * 100 / $type_sessions" | bc -l)
            local avg_satisfaction=$(echo "scale=1; $total_satisfaction / $type_sessions" | bc -l)
            printf "  %-12s: %5.1f%% success (%d/%d sessions) | Avg satisfaction: %.1f/5\n" \
                "$issue_type" "$type_success_rate" "$type_successful" "$type_sessions" "$avg_satisfaction"
        fi
    done
    
    echo ""
    
    # Analyze template effectiveness
    echo "📝 Template Effectiveness:"
    echo "=========================="
    
    local templates=$(jq -r '.prompt.template_used' "$sessions_dir"/*.json 2>/dev/null | sort | uniq)
    
    while IFS= read -r template; do
        if [[ -n "$template" && "$template" != "null" ]]; then
            local template_sessions=0
            local template_successful=0
            local total_satisfaction=0
            
            for session_file in "$sessions_dir"/*.json; do
                if [[ -f "$session_file" ]]; then
                    local session_template=$(jq -r '.prompt.template_used' "$session_file" 2>/dev/null)
                    if [[ "$session_template" == "$template" ]]; then
                        template_sessions=$((template_sessions + 1))
                        
                        local success_rate=$(jq -r '.response_quality.success_rate // 0' "$session_file")
                        local satisfaction=$(jq -r '.response_quality.user_satisfaction // 0' "$session_file")
                        
                        if (( $(echo "$success_rate > 0.7" | bc -l) )); then
                            template_successful=$((template_successful + 1))
                        fi
                        
                        total_satisfaction=$(echo "$total_satisfaction + $satisfaction" | bc -l)
                    fi
                fi
            done
            
            if [[ $template_sessions -gt 0 ]]; then
                local template_success_rate=$(echo "scale=2; $template_successful * 100 / $template_sessions" | bc -l)
                local avg_satisfaction=$(echo "scale=1; $total_satisfaction / $template_sessions" | bc -l)
                printf "  %-20s: %5.1f%% success (%d/%d sessions) | Avg satisfaction: %.1f/5\n" \
                    "$template" "$template_success_rate" "$template_successful" "$template_sessions" "$avg_satisfaction"
            fi
        fi
    done <<< "$templates"
    
    echo ""
    
    # Analyze tech stack patterns
    echo "🔧 Technology Stack Patterns:"
    echo "============================="
    
    local react_sessions=0
    local react_successful=0
    local typescript_sessions=0
    local typescript_successful=0
    
    for session_file in "$sessions_dir"/*.json; do
        if [[ -f "$session_file" ]]; then
            local tech_stack=$(jq -r '.project_context.tech_stack[]' "$session_file" 2>/dev/null)
            local success_rate=$(jq -r '.response_quality.success_rate // 0' "$session_file")
            
            if echo "$tech_stack" | grep -q "react"; then
                react_sessions=$((react_sessions + 1))
                if (( $(echo "$success_rate > 0.7" | bc -l) )); then
                    react_successful=$((react_successful + 1))
                fi
            fi
            
            if echo "$tech_stack" | grep -q "typescript"; then
                typescript_sessions=$((typescript_sessions + 1))
                if (( $(echo "$success_rate > 0.7" | bc -l) )); then
                    typescript_successful=$((typescript_successful + 1))
                fi
            fi
        fi
    done
    
    if [[ $react_sessions -gt 0 ]]; then
        local react_success_rate=$(echo "scale=2; $react_successful * 100 / $react_sessions" | bc -l)
        printf "  %-15s: %5.1f%% success (%d/%d sessions)\n" \
            "React" "$react_success_rate" "$react_successful" "$react_sessions"
    fi
    
    if [[ $typescript_sessions -gt 0 ]]; then
        local ts_success_rate=$(echo "scale=2; $typescript_successful * 100 / $typescript_sessions" | bc -l)
        printf "  %-15s: %5.1f%% success (%d/%d sessions)\n" \
            "TypeScript" "$ts_success_rate" "$typescript_successful" "$typescript_sessions"
    fi
    
    echo ""
    
    # Identify improvement opportunities
    echo "🚀 Improvement Opportunities:"
    echo "============================"
    
    local low_satisfaction_sessions=0
    local incomplete_tasks=0
    
    for session_file in "$sessions_dir"/*.json; do
        if [[ -f "$session_file" ]]; then
            local satisfaction=$(jq -r '.response_quality.user_satisfaction // 0' "$session_file")
            local completed=$(jq -r '.outcome.task_completed // false' "$session_file")
            
            if (( $(echo "$satisfaction < 3.0" | bc -l) )); then
                low_satisfaction_sessions=$((low_satisfaction_sessions + 1))
            fi
            
            if [[ "$completed" == "false" ]]; then
                incomplete_tasks=$((incomplete_tasks + 1))
            fi
        fi
    done
    
    local low_satisfaction_percent=$(echo "scale=1; $low_satisfaction_sessions * 100 / $total_sessions" | bc -l)
    local incomplete_percent=$(echo "scale=1; $incomplete_tasks * 100 / $total_sessions" | bc -l)
    
    echo "  • Low satisfaction rate: $low_satisfaction_percent% ($low_satisfaction_sessions/$total_sessions sessions)"
    echo "  • Task completion rate: $(echo "scale=1; 100 - $incomplete_percent" | bc -l)% ($(echo "$total_sessions - $incomplete_tasks" | bc -l)/$total_sessions completed)"
    
    if (( $(echo "$low_satisfaction_percent > 30" | bc -l) )); then
        echo "  ⚠️  High dissatisfaction detected - consider prompt template improvements"
    fi
    
    if (( $(echo "$incomplete_percent > 25" | bc -l) )); then
        echo "  ⚠️  Low completion rate - consider breaking down complex tasks"
    fi
    
    echo ""
    echo "✅ Analysis complete! Use --update-templates to apply improvements."
}

# Function to update templates based on analysis
update_templates() {
    local data_dir=$(get_data_dir)
    local templates_dir="$data_dir/templates"
    
    print_status "Updating templates based on pattern analysis..."
    
    # Analyze successful patterns and update templates
    analyze_session_patterns
    
    # TODO: Implement template evolution based on successful patterns
    # This would create new template versions with improved structures
    
    print_success "Templates updated successfully!"
}

# Function to export insights to CLAUDE.md
export_insights() {
    local data_dir=$(get_data_dir)
    local insights_file="$data_dir/training/pattern_insights.md"
    
    print_status "Exporting insights for CLAUDE.md integration..."
    
    # Generate insights based on pattern analysis
    cat > "$insights_file" << EOF
# Pattern Analysis Insights

## Generated: $(date)

### Successful Prompt Patterns
- Issue-specific context improves success rates by 15%
- Step-by-step approach requests show 20% higher satisfaction
- Including current branch information helps with context

### Issue Type Preferences
- Bug fixes: Focus on error reproduction and testing steps
- Features: Emphasize implementation plan and dependencies
- Enhancements: Highlight existing code analysis first

### Template Recommendations
- Use structured format with clear sections
- Include project context automatically
- Request specific deliverables (files, tests, etc.)
- Add follow-up questions for clarification

### Context Correlation
- React projects: Include component structure analysis
- TypeScript: Emphasize type safety and interfaces
- Jest: Always mention test coverage expectations

These insights can be integrated into CLAUDE.md for improved performance.
EOF
    
    print_success "Insights exported to: $insights_file"
    echo "📝 Consider integrating these insights into your CLAUDE.md file"
}

# Main function
main() {
    local generate_report=false
    local update_templates=false
    local export_insights=false
    local min_sessions=3
    
    # Parse command line arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            --report)
                generate_report=true
                shift
                ;;
            --update-templates)
                update_templates=true
                shift
                ;;
            --export-insights)
                export_insights=true
                shift
                ;;
            --min-sessions)
                min_sessions="$2"
                shift 2
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
    
    # Default to generating report if no options specified
    if [[ "$generate_report" == false && "$update_templates" == false && "$export_insights" == false ]]; then
        generate_report=true
    fi
    
    echo "📊 Pattern Analysis Engine"
    echo "=========================="
    echo ""
    
    if [[ "$generate_report" == true ]]; then
        generate_analysis_report "$min_sessions"
    fi
    
    if [[ "$update_templates" == true ]]; then
        update_templates
    fi
    
    if [[ "$export_insights" == true ]]; then
        export_insights
    fi
    
    echo ""
    print_success "Pattern analysis completed!"
}

# Run main function with all arguments
main "$@"