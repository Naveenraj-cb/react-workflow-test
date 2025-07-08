# Prompt Storage & Pattern Analysis System

This directory contains the data storage and analysis system for improving Claude's performance over time.

## Directory Structure

### `/sessions/`
Stores individual session logs with:
- Original prompts and responses
- Context information (issue, branch, files)
- Outcome metrics (success, time, satisfaction)
- Metadata for analysis

### `/patterns/`
Contains analyzed patterns:
- `successful_patterns.json` - Proven effective prompt elements
- `failed_patterns.json` - Patterns that didn't work well
- `context_patterns.json` - Context-specific successful strategies
- `template_patterns.json` - Template evolution data

### `/templates/`
Evolved prompt templates:
- `linear_task_v1.template` - Original template
- `linear_task_v2.template` - Improved version
- `bug_fix.template` - Bug-specific template
- `feature.template` - Feature-specific template

### `/analytics/`
Performance metrics and reports:
- `prompt_effectiveness.json` - Success rate tracking
- `user_satisfaction.json` - User feedback metrics
- `improvement_trends.json` - Progress over time
- `common_patterns.json` - Frequently successful elements

### `/training/`
Claude training data:
- `pattern_injections.md` - Patterns to add to CLAUDE.md
- `context_awareness.json` - Project-specific learnings
- `adaptive_prompts.json` - Dynamic prompt adjustments

## Data Format

Session logs follow this JSON structure:
```json
{
  "timestamp": "2024-01-15T10:30:00Z",
  "session_id": "uuid",
  "issue_id": "COD-294",
  "issue_type": "feature|bug|enhancement",
  "project_context": {
    "branch": "feature/cod-294",
    "files_changed": ["src/components/", "tests/"],
    "tech_stack": ["React", "TypeScript", "Jest"]
  },
  "prompt": {
    "original": "Generated prompt text",
    "modifications": "User modifications if any",
    "template_used": "linear_task_v1"
  },
  "response_quality": {
    "success_rate": 0.85,
    "time_to_completion": "45m",
    "user_satisfaction": 4.2,
    "follow_up_needed": false
  },
  "patterns_identified": [
    "specific_file_analysis",
    "step_by_step_approach",
    "dependency_checking"
  ],
  "outcome": {
    "task_completed": true,
    "files_modified": 5,
    "tests_passed": true,
    "commit_successful": true
  }
}
```

## Usage

The system automatically:
1. Logs every prompt/response session
2. Analyzes patterns for effectiveness
3. Updates prompt templates
4. Improves CLAUDE.md with learned patterns
5. Adapts future prompts based on success history