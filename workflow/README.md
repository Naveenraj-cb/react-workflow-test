# Workflow Scripts

This directory contains automation scripts for managing Linear tasks and GitHub PRs.

## Tools and Scripts

- `create-task-branch.sh` - Create and checkout branches for Linear tasks
- `perform-task.sh` - Get AI assistance for performing Linear tasks
- `raise-pr.sh` - Creates GitHub pull requests with Linear integration
- `mark-task-complete.sh` - Marks Linear tasks as complete and adds metrics
- `sync-to-client.sh` - Sync changes from private repo to client repo
- `common-utils.sh` - Shared utilities and functions for all scripts

## Workflow

### Standard Workflow (Single Repo)
1. Use `create-task-branch.sh` to create and checkout feature branch from Linear task
2. Use `perform-task.sh` to get AI assistance for the task
3. Make changes and commit with appropriate prefix ([AI] or [DEV])
4. Use `raise-pr.sh` to create pull request
5. Use `mark-task-complete.sh` to mark Linear task as complete and add metrics

### Cross-Repo Workflow (Private → Client)
1. Copy client repo to your private repository
2. Add workflow directory to private repo and configure `.env.local`
3. Follow standard workflow (steps 1-5 above) in private repo
4. Use `sync-to-client.sh` to transfer changes to client repo without commit history
5. Review and commit changes in client repo with clean commit messages

## Setup

1. Copy `.env.local.example` to `.env.local` and add your tokens:
   ```bash
   LINEAR_API_TOKEN="your-linear-token"
   GITHUB_TOKEN="your-github-token"
   GITHUB_REPO="owner/repo-name"
   
   # For cross-repo workflow only
   CLIENT_REPO_PATH="/path/to/client/repository"
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

### 1. Create Task Branch Script
```bash
# Create branch from Linear issue
./create-task-branch.sh -i COD-294

# Create branch from different base branch
./create-task-branch.sh -i COD-294 -b develop

# Create branch but don't checkout locally
./create-task-branch.sh -i COD-294 --skip-checkout
```

### 2. Perform Task Script
```bash
# Get AI assistance for a Linear task
./perform-task.sh -i COD-294

# Use with custom prompt
./perform-task.sh -i COD-294 -p "Help me implement this feature"
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

### 4. Mark Task Complete Script
```bash
# Mark Linear task as complete
./mark-task-complete.sh -i COD-294

# Skip status update, only add metrics
./mark-task-complete.sh -i COD-294 --skip-status-update
```

### 5. Sync to Client Script
```bash
# Sync current branch changes
./sync-to-client.sh

# Sync specific commit range
./sync-to-client.sh -r "abc123..def456"

# Sync single commit
./sync-to-client.sh -c "abc123"

# Sync last 5 commits
./sync-to-client.sh --last 5

# Sync commits since yesterday
./sync-to-client.sh --since "yesterday"

# Preview changes without copying (dry run)
./sync-to-client.sh --dry-run

# Sync with custom base branch
./sync-to-client.sh -b develop

# Sync with custom client path
./sync-to-client.sh --client-path "/path/to/client/repo"

# Exclude additional files
./sync-to-client.sh --exclude "*.test.js" --exclude "docs/"
```

## Cross-Repo Workflow Details

### Setup for Cross-Repo Development

1. **Clone client repo to your private space:**
   ```bash
   git clone client-repo-url my-private-client-copy
   cd my-private-client-copy
   ```

2. **Add workflow directory:**
   ```bash
   # Copy the workflow directory to your private repo
   cp -r /path/to/workflow ./workflow
   ```

3. **Configure environment:**
   ```bash
   cd workflow
   cp .env.local.example .env.local
   # Edit .env.local with your tokens and set CLIENT_REPO_PATH
   ```

### Working with Cross-Repo Sync

The sync script intelligently handles:
- **Base branch detection**: Automatically detects the branch your feature was created from
- **File filtering**: Excludes workflow files, configs, and other private repo artifacts
- **Multiple sync modes**: Current branch, commit ranges, single commits, or time-based
- **Safety checks**: Validates repos, checks working state, previews changes
- **Clean transfer**: Copies files without commit history for clean client repo

### Example Cross-Repo Workflow

```bash
# 1. Create feature branch in private repo
./workflow/create-task-branch.sh -i LIN-123

# 2. Get AI assistance
./workflow/perform-task.sh -i LIN-123

# 3. Work on feature, make commits with [AI]/[DEV] prefixes
git add .
git commit -m "[AI] Implement user authentication"

# 4. Create PR in private repo
./workflow/raise-pr.sh -i LIN-123

# 5. Complete task (this will prompt for sync)
./workflow/mark-task-complete.sh -i LIN-123

# 6. Or manually sync anytime
./workflow/sync-to-client.sh --dry-run  # Preview
./workflow/sync-to-client.sh            # Actually sync

# 7. Go to client repo and commit clean
cd /path/to/client/repo
git status  # See synced changes
git add .
git commit -m "Implement user authentication feature"
```

This approach keeps your private repo with detailed [AI]/[DEV] commit history while maintaining a clean, professional commit history in the client repository.