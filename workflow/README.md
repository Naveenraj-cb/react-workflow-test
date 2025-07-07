# Workflow Scripts

This directory contains automation scripts for managing Linear tasks and GitHub PRs.

## Tools and Scripts

- `task-branch-checkout.sh` - Checkout branches for Linear tasks
- `prompt-claude.sh` - Utility for prompting Claude AI
- `raise-pr.sh` - Creates GitHub pull requests with Linear integration
- `complete-task.sh` - Marks Linear tasks as complete and adds metrics

## Workflow

1. Use `task-branch-checkout.sh` to create and checkout feature branch from Linear task
2. Use `prompt-claude.sh` to get AI assistance for the task
3. Make changes and commit with appropriate prefix ([AI] or [DEV])
4. Use `raise-pr.sh` to create pull request
5. Use `complete-task.sh` to mark Linear task as complete and add metrics

## Setup

1. Copy `.env.local.example` to `.env.local` and add your tokens:
   ```bash
   LINEAR_API_TOKEN="your-linear-token"
   GITHUB_TOKEN="your-github-token"
   ```

2. Install required tools:
   ```bash
   # macOS
   brew install gh jq
   
   # Ubuntu
   sudo apt install gh jq
   ```

3. Authenticate GitHub CLI:
   ```bash
   gh auth login
   ```

## Usage Examples

### 1. Task Branch Checkout Script
```bash
# Create branch from Linear issue
./task-branch-checkout.sh -i COD-294

# Create branch from different base branch
./task-branch-checkout.sh -i COD-294 -b develop

# Create branch but don't checkout locally
./task-branch-checkout.sh -i COD-294 --skip-checkout
```

### 2. Prompt Claude Script
```bash
# Get AI assistance for a Linear task
./prompt-claude.sh -i COD-294

# Use with custom prompt
./prompt-claude.sh -i COD-294 -p "Help me implement this feature"
```

### 3. Raise PR Script
```bash
# Auto-detect issue from branch name
./raise-pr.sh

# Specify issue ID explicitly
./raise-pr.sh -i COD-294

# Custom PR to develop branch
./raise-pr.sh -b develop

# Custom title and description
./raise-pr.sh -t "Add new feature" -d "This PR adds..."
```

### 4. Complete Task Script
```bash
# Mark Linear task as complete
./complete-task.sh -i COD-294

# Skip status update, only add metrics
./complete-task.sh -i COD-294 --skip-status-update
```