# Prompt Storage & Pattern Analysis System

## Overview

This system creates a self-improving workflow that stores prompts over time and trains Claude to analyze patterns for continuous improvement. Every interaction is logged, analyzed, and used to enhance future prompts.

## System Components

### 1. Data Storage (`workflow/data/`)
```
data/
├── sessions/           # Individual session logs with prompts & outcomes
├── patterns/          # Analyzed successful/failed patterns  
├── templates/         # Evolved prompt templates
├── analytics/         # Performance metrics and reports
└── training/          # Claude training data and insights
```

### 2. Core Scripts

#### `perform-task.sh` (Enhanced)
- **Auto-logs** every prompt and response with metadata
- **Adaptive prompting** based on learned patterns
- **User feedback collection** for continuous improvement
- **Context awareness** (tech stack, issue type, recent changes)

#### `analyze-patterns.sh`
- **Pattern recognition** from stored sessions
- **Success rate analysis** by issue type and template
- **Technology-specific insights** (React, TypeScript, etc.)
- **Performance reports** with improvement recommendations

#### `update-claude-guidelines.sh`
- **Auto-updates CLAUDE.md** with learned patterns
- **Context-specific guidelines** based on successful sessions
- **Backup and versioning** of guideline changes
- **Statistical validation** before applying updates

#### `ab-test-prompts.sh`
- **A/B testing framework** for prompt variations
- **Statistical significance** testing
- **Automatic winner selection** based on performance
- **User assignment** via consistent hashing

### 3. Enhanced Common Utilities (`common-utils.sh`)

New functions added:
- `store_session_data()` - Log session with full context
- `update_session_outcome()` - Record results and feedback
- `analyze_session_patterns()` - Extract successful patterns
- `get_session_feedback()` - Collect user satisfaction ratings
- `get_project_context()` - Auto-detect tech stack and changes
- `generate_session_id()` - Create unique session identifiers

## How It Works

### Session Lifecycle

1. **Prompt Generation**
   - `perform-task.sh` analyzes issue type and tech stack
   - Selects optimal template based on historical success
   - Generates context-aware prompt with project details

2. **Session Logging**
   - Stores prompt, context, and metadata before Claude interaction
   - Assigns unique session ID for tracking
   - Records tech stack, branch, recent file changes

3. **User Feedback**
   - Collects satisfaction rating (1-5 scale)
   - Records task completion status
   - Tracks files modified and success metrics

4. **Pattern Analysis**
   - Identifies successful prompt elements
   - Correlates success with context (issue type, tech stack)
   - Updates pattern database automatically

5. **Continuous Improvement**
   - Evolves prompt templates based on successful patterns
   - Updates CLAUDE.md with learned guidelines
   - Adapts future prompts using historical data

### Adaptive Prompting

The system automatically selects the best prompt template based on:

- **Issue Type**: bug, feature, enhancement, task
- **Tech Stack**: React, TypeScript, Jest, Next.js, etc.
- **Historical Success**: Templates with >70% success rate preferred
- **Context Patterns**: Project-specific successful approaches

### Pattern Learning

Analyzes sessions to identify:

- **High-performing prompt structures**
- **Context-specific success factors**
- **Issue type preferences**
- **Technology-specific patterns**
- **User satisfaction correlations**

## Usage

### Basic Usage
```bash
# Use enhanced perform-task script
./workflow/perform-task.sh -i COD-294

# System automatically:
# 1. Selects best template for issue type + tech stack
# 2. Logs session with full context
# 3. Collects feedback after Claude interaction
# 4. Updates patterns for future improvement
```

### Analysis & Reporting
```bash
# Generate pattern analysis report
./workflow/analyze-patterns.sh --report

# Update CLAUDE.md with learned patterns
./workflow/update-claude-guidelines.sh --backup

# Preview changes without applying
./workflow/update-claude-guidelines.sh --dry-run
```

### A/B Testing
```bash
# Create new A/B test for prompt variations
./workflow/ab-test-prompts.sh --create-test bug_fix_v2

# Check test status
./workflow/ab-test-prompts.sh --status bug_fix_v2

# Stop test and see results
./workflow/ab-test-prompts.sh --stop-test bug_fix_v2 --report bug_fix_v2
```

## Key Features

### 🧠 **Intelligent Adaptation**
- Learns from every interaction
- Adapts to project-specific patterns
- Improves over time automatically

### 📊 **Comprehensive Analytics**
- Success rate tracking by issue type
- User satisfaction monitoring
- Template effectiveness analysis
- Technology-specific insights

### 🎯 **Context Awareness**
- Auto-detects tech stack from project files
- Includes recent changes for context
- Adapts to team and project patterns

### 🔬 **Scientific Testing**
- A/B testing framework for prompt variations
- Statistical significance validation
- Automatic winner selection

### 🤖 **Self-Improving**
- Auto-updates CLAUDE.md with successful patterns
- Evolves prompt templates based on data
- Continuous feedback loop integration

## Benefits

1. **Better Prompts Over Time**: Each interaction improves future performance
2. **Project-Specific Optimization**: Learns your codebase and team patterns
3. **Data-Driven Improvements**: Uses real performance data, not assumptions
4. **Automated Learning**: No manual intervention required
5. **Scientific Validation**: A/B testing ensures improvements are real
6. **Team Knowledge Sharing**: Successful patterns benefit entire team

## Data Privacy & Security

- **Local Storage Only**: All data stays on your machine
- **No External Transmission**: Session data never leaves your environment
- **Configurable Retention**: Automatic cleanup of old session data
- **Sanitized Logging**: API keys and secrets automatically filtered

## Future Enhancements

- **Cross-project pattern sharing** for team learning
- **Integration with IDE extensions** for real-time suggestions
- **Advanced ML models** for pattern recognition
- **Automated prompt optimization** using genetic algorithms
- **Team analytics dashboard** for collaboration insights

This system transforms Claude from a static assistant into a continuously learning partner that gets better at understanding your project and generating effective prompts over time.