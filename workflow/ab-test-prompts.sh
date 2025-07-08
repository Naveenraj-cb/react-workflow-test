#!/bin/bash

# A/B Testing Framework for Prompt Variations
# This script manages A/B testing of different prompt templates

set -e

# Load common utilities
source "$(dirname "$0")/common-utils.sh"

# Function to show help
show_help() {
    cat << 'EOF'
🧪 A/B Testing Framework for Prompts
===================================

USAGE:
    ./ab-test-prompts.sh [OPTIONS]

OPTIONS:
    --create-test NAME      Create new A/B test with variants
    --list-tests           List all active A/B tests
    --status TEST_NAME     Show status of specific test
    --stop-test TEST_NAME  Stop A/B test and analyze results
    --report TEST_NAME     Generate detailed test report
    -h, --help            Show this help message

EXAMPLES:
    # Create new A/B test for bug fix prompts
    ./ab-test-prompts.sh --create-test bug_fix_v2

    # Check status of running test
    ./ab-test-prompts.sh --status bug_fix_v2

    # Stop test and see results
    ./ab-test-prompts.sh --stop-test bug_fix_v2 --report bug_fix_v2

This framework allows you to:
1. Test different prompt variations simultaneously
2. Randomly assign users to test variants
3. Track performance metrics for each variant
4. Automatically determine winning prompts
5. Integrate successful variants into production
EOF
}

# Function to create new A/B test
create_ab_test() {
    local test_name="$1"
    local data_dir=$(get_data_dir)
    local ab_tests_dir="$data_dir/ab_tests"
    
    ensure_data_dir
    mkdir -p "$ab_tests_dir"
    
    local test_file="$ab_tests_dir/${test_name}.json"
    
    if [[ -f "$test_file" ]]; then
        print_error "A/B test '$test_name' already exists"
        return 1
    fi
    
    echo "🧪 Creating A/B Test: $test_name"
    echo "==============================="
    echo ""
    
    # Get test parameters
    echo "Enter test description:"
    read -p "> " test_description
    
    echo ""
    echo "Enter variant A name (control):"
    read -p "> " variant_a_name
    
    echo "Enter variant A template:"
    read -p "> " variant_a_template
    
    echo ""
    echo "Enter variant B name (test):"
    read -p "> " variant_b_name
    
    echo "Enter variant B template:"
    read -p "> " variant_b_template
    
    echo ""
    echo "Enter target issue types (comma-separated, e.g., bug,feature):"
    read -p "> " target_issue_types
    
    echo ""
    echo "Enter minimum sample size per variant (default: 10):"
    read -p "> " min_sample_size
    min_sample_size=${min_sample_size:-10}
    
    # Create test configuration
    jq -n \
        --arg test_name "$test_name" \
        --arg description "$test_description" \
        --arg variant_a_name "$variant_a_name" \
        --arg variant_a_template "$variant_a_template" \
        --arg variant_b_name "$variant_b_name" \
        --arg variant_b_template "$variant_b_template" \
        --arg target_issue_types "$target_issue_types" \
        --arg min_sample_size "$min_sample_size" \
        '{
            test_name: $test_name,
            description: $description,
            created: now | strftime("%Y-%m-%dT%H:%M:%SZ"),
            status: "active",
            variants: {
                A: {
                    name: $variant_a_name,
                    template: $variant_a_template,
                    sessions: [],
                    metrics: {
                        total_sessions: 0,
                        successful_sessions: 0,
                        avg_satisfaction: 0,
                        avg_success_rate: 0
                    }
                },
                B: {
                    name: $variant_b_name,
                    template: $variant_b_template,
                    sessions: [],
                    metrics: {
                        total_sessions: 0,
                        successful_sessions: 0,
                        avg_satisfaction: 0,
                        avg_success_rate: 0
                    }
                }
            },
            config: {
                target_issue_types: ($target_issue_types | split(",")),
                min_sample_size: ($min_sample_size | tonumber),
                traffic_split: 50,
                success_threshold: 0.7,
                satisfaction_threshold: 3.5
            },
            results: {
                statistical_significance: false,
                winning_variant: null,
                confidence_level: 0
            }
        }' > "$test_file"
    
    print_success "A/B test '$test_name' created successfully!"
    echo "📊 Test will automatically assign users to variants when they use perform-task.sh"
}

# Function to list active tests
list_ab_tests() {
    local data_dir=$(get_data_dir)
    local ab_tests_dir="$data_dir/ab_tests"
    
    if [[ ! -d "$ab_tests_dir" ]]; then
        print_warning "No A/B tests directory found"
        return 0
    fi
    
    echo "🧪 Active A/B Tests"
    echo "=================="
    echo ""
    
    local tests_found=false
    
    for test_file in "$ab_tests_dir"/*.json; do
        if [[ -f "$test_file" ]]; then
            tests_found=true
            local test_name=$(jq -r '.test_name' "$test_file")
            local status=$(jq -r '.status' "$test_file")
            local created=$(jq -r '.created' "$test_file")
            local total_sessions_a=$(jq -r '.variants.A.metrics.total_sessions' "$test_file")
            local total_sessions_b=$(jq -r '.variants.B.metrics.total_sessions' "$test_file")
            
            printf "  %-20s Status: %-8s Created: %-10s Sessions: A=%d, B=%d\n" \
                "$test_name" "$status" "${created%T*}" "$total_sessions_a" "$total_sessions_b"
        fi
    done
    
    if [[ "$tests_found" == false ]]; then
        echo "  No active A/B tests found"
    fi
    echo ""
}

# Function to show test status
show_test_status() {
    local test_name="$1"
    local data_dir=$(get_data_dir)
    local test_file="$data_dir/ab_tests/${test_name}.json"
    
    if [[ ! -f "$test_file" ]]; then
        print_error "A/B test '$test_name' not found"
        return 1
    fi
    
    echo "🧪 A/B Test Status: $test_name"
    echo "=============================="
    echo ""
    
    local description=$(jq -r '.description' "$test_file")
    local status=$(jq -r '.status' "$test_file")
    local created=$(jq -r '.created' "$test_file")
    
    echo "Description: $description"
    echo "Status: $status"
    echo "Created: $created"
    echo ""
    
    echo "Variant Performance:"
    echo "==================="
    
    local variant_a_name=$(jq -r '.variants.A.name' "$test_file")
    local variant_a_sessions=$(jq -r '.variants.A.metrics.total_sessions' "$test_file")
    local variant_a_success=$(jq -r '.variants.A.metrics.avg_success_rate' "$test_file")
    local variant_a_satisfaction=$(jq -r '.variants.A.metrics.avg_satisfaction' "$test_file")
    
    local variant_b_name=$(jq -r '.variants.B.name' "$test_file")
    local variant_b_sessions=$(jq -r '.variants.B.metrics.total_sessions' "$test_file")
    local variant_b_success=$(jq -r '.variants.B.metrics.avg_success_rate' "$test_file")
    local variant_b_satisfaction=$(jq -r '.variants.B.metrics.avg_satisfaction' "$test_file")
    
    printf "  Variant A (%s):\n" "$variant_a_name"
    printf "    Sessions: %d\n" "$variant_a_sessions"
    printf "    Success Rate: %.2f%%\n" "$(echo "$variant_a_success * 100" | bc -l)"
    printf "    Avg Satisfaction: %.1f/5\n" "$variant_a_satisfaction"
    echo ""
    
    printf "  Variant B (%s):\n" "$variant_b_name"
    printf "    Sessions: %d\n" "$variant_b_sessions"
    printf "    Success Rate: %.2f%%\n" "$(echo "$variant_b_success * 100" | bc -l)"
    printf "    Avg Satisfaction: %.1f/5\n" "$variant_b_satisfaction"
    echo ""
    
    # Check for statistical significance
    local min_sample_size=$(jq -r '.config.min_sample_size' "$test_file")
    local statistical_significance=$(jq -r '.results.statistical_significance' "$test_file")
    
    if [[ $variant_a_sessions -ge $min_sample_size && $variant_b_sessions -ge $min_sample_size ]]; then
        echo "📊 Sample size reached. Statistical analysis available."
        if [[ "$statistical_significance" == "true" ]]; then
            local winning_variant=$(jq -r '.results.winning_variant' "$test_file")
            echo "🏆 Winning variant: $winning_variant"
        else
            echo "⚖️  No statistically significant difference detected"
        fi
    else
        echo "⏳ Need more data: A needs $((min_sample_size - variant_a_sessions)) more, B needs $((min_sample_size - variant_b_sessions)) more sessions"
    fi
}

# Function to stop test and analyze results
stop_ab_test() {
    local test_name="$1"
    local data_dir=$(get_data_dir)
    local test_file="$data_dir/ab_tests/${test_name}.json"
    
    if [[ ! -f "$test_file" ]]; then
        print_error "A/B test '$test_name' not found"
        return 1
    fi
    
    print_status "Stopping A/B test: $test_name"
    
    # Update test status
    jq '.status = "stopped" | .stopped = now | strftime("%Y-%m-%dT%H:%M:%SZ")' \
        "$test_file" > "$test_file.tmp" && mv "$test_file.tmp" "$test_file"
    
    print_success "A/B test '$test_name' stopped successfully"
}

# Function to generate test report
generate_test_report() {
    local test_name="$1"
    local data_dir=$(get_data_dir)
    local test_file="$data_dir/ab_tests/${test_name}.json"
    
    if [[ ! -f "$test_file" ]]; then
        print_error "A/B test '$test_name' not found"
        return 1
    fi
    
    echo "📊 A/B Test Report: $test_name"
    echo "=============================="
    echo ""
    
    # Show detailed analysis
    show_test_status "$test_name"
    
    echo ""
    echo "Recommendations:"
    echo "================"
    
    local variant_a_success=$(jq -r '.variants.A.metrics.avg_success_rate' "$test_file")
    local variant_b_success=$(jq -r '.variants.B.metrics.avg_success_rate' "$test_file")
    local variant_a_satisfaction=$(jq -r '.variants.A.metrics.avg_satisfaction' "$test_file")
    local variant_b_satisfaction=$(jq -r '.variants.B.metrics.avg_satisfaction' "$test_file")
    
    # Determine winner
    if (( $(echo "$variant_b_success > $variant_a_success" | bc -l) )) && (( $(echo "$variant_b_satisfaction > $variant_a_satisfaction" | bc -l) )); then
        local variant_b_name=$(jq -r '.variants.B.name' "$test_file")
        echo "🏆 Recommend implementing Variant B ($variant_b_name)"
        echo "  - Higher success rate: $(echo "scale=1; ($variant_b_success - $variant_a_success) * 100" | bc -l)% improvement"
        echo "  - Higher satisfaction: $(echo "scale=1; $variant_b_satisfaction - $variant_a_satisfaction" | bc -l) point improvement"
    elif (( $(echo "$variant_a_success > $variant_b_success" | bc -l) )) && (( $(echo "$variant_a_satisfaction > $variant_b_satisfaction" | bc -l) )); then
        local variant_a_name=$(jq -r '.variants.A.name' "$test_file")
        echo "🏆 Recommend keeping Variant A ($variant_a_name)"
        echo "  - Higher success rate: $(echo "scale=1; ($variant_a_success - $variant_b_success) * 100" | bc -l)% better"
        echo "  - Higher satisfaction: $(echo "scale=1; $variant_a_satisfaction - $variant_b_satisfaction" | bc -l) point better"
    else
        echo "⚖️  No clear winner. Consider:"
        echo "  - Running test longer for more data"
        echo "  - Testing more dramatic variations"
        echo "  - Keeping current approach"
    fi
}

# Function to get variant for user (used by perform-task.sh)
get_ab_test_variant() {
    local issue_type="$1"
    local user_id="${2:-$(whoami)}"
    local data_dir=$(get_data_dir)
    local ab_tests_dir="$data_dir/ab_tests"
    
    if [[ ! -d "$ab_tests_dir" ]]; then
        echo ""
        return
    fi
    
    # Find active test for this issue type
    for test_file in "$ab_tests_dir"/*.json; do
        if [[ -f "$test_file" ]]; then
            local status=$(jq -r '.status' "$test_file")
            local target_types=$(jq -r '.config.target_issue_types[]' "$test_file" 2>/dev/null)
            
            if [[ "$status" == "active" ]] && echo "$target_types" | grep -q "$issue_type"; then
                # Use hash of user_id + issue_type to consistently assign variant
                local hash=$(echo "${user_id}_${issue_type}" | md5sum | cut -c1-2)
                local hash_decimal=$((0x$hash))
                local variant_assignment=$((hash_decimal % 2))
                
                if [[ $variant_assignment -eq 0 ]]; then
                    local test_name=$(jq -r '.test_name' "$test_file")
                    local template=$(jq -r '.variants.A.template' "$test_file")
                    echo "${test_name}:A:$template"
                else
                    local test_name=$(jq -r '.test_name' "$test_file")
                    local template=$(jq -r '.variants.B.template' "$test_file")
                    echo "${test_name}:B:$template"
                fi
                return
            fi
        fi
    done
    
    echo ""
}

# Main function
main() {
    local action=""
    local test_name=""
    
    # Parse command line arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            --create-test)
                action="create"
                test_name="$2"
                shift 2
                ;;
            --list-tests)
                action="list"
                shift
                ;;
            --status)
                action="status"
                test_name="$2"
                shift 2
                ;;
            --stop-test)
                action="stop"
                test_name="$2"
                shift 2
                ;;
            --report)
                action="report"
                test_name="$2"
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
    
    if [[ -z "$action" ]]; then
        action="list"
    fi
    
    case "$action" in
        create)
            if [[ -z "$test_name" ]]; then
                print_error "Test name required for --create-test"
                exit 1
            fi
            create_ab_test "$test_name"
            ;;
        list)
            list_ab_tests
            ;;
        status)
            if [[ -z "$test_name" ]]; then
                print_error "Test name required for --status"
                exit 1
            fi
            show_test_status "$test_name"
            ;;
        stop)
            if [[ -z "$test_name" ]]; then
                print_error "Test name required for --stop-test"
                exit 1
            fi
            stop_ab_test "$test_name"
            ;;
        report)
            if [[ -z "$test_name" ]]; then
                print_error "Test name required for --report"
                exit 1
            fi
            generate_test_report "$test_name"
            ;;
        *)
            print_error "Unknown action: $action"
            exit 1
            ;;
    esac
}

# Run main function with all arguments
main "$@"