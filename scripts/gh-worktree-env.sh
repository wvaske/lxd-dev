#!/bin/bash
# Clone a GitHub repo (if needed) and create worktree environment
# Combines gh CLI with worktree-env.sh for a streamlined workflow
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

usage() {
    cat << EOF
Usage: $(basename "$0") <github-repo> <branch> [options]

Clone a GitHub repo and create a worktree environment for a branch.

Arguments:
  github-repo       GitHub repo in owner/repo format (e.g., wvaske/dlio_benchmark)
  branch            Branch name for the worktree

Options:
  --clone-dir DIR   Directory to clone into (default: ~/Projects)
  --stack STACK     Development stack: nodejs, python, rust, go (default: auto-detect)
  --image IMAGE     Base image (default: cdev-<stack> if exists, else ubuntu-base)
  --cpu CORES       CPU limit (default: 4)
  --memory SIZE     Memory limit (default: 8GB)
  --base BRANCH     Base branch when creating new branch (default: main)
  --fork            Fork the repo first (for contributing to others' repos)
  -h, --help        Show this help message

Examples:
  # Work on existing branch
  $(basename "$0") wvaske/dlio_benchmark feature/checkpoint --stack python

  # Create new feature branch
  $(basename "$0") wvaske/dlio_benchmark feature/my-improvement --stack python

  # Fork and work on someone else's repo
  $(basename "$0") argonne-lcf/dlio_benchmark my-fix --fork --stack python

  # Multiple parallel branches
  $(basename "$0") wvaske/dlio_benchmark bugfix/issue-149 --stack python
  $(basename "$0") wvaske/dlio_benchmark feature/new-loader --stack python
EOF
    exit "${1:-0}"
}

# Defaults
CLONE_DIR="$HOME/Projects"
STACK=""
IMAGE=""
CPU="4"
MEMORY="8GB"
BASE_BRANCH="main"
FORK=false

# Parse arguments
REPO=""
BRANCH=""

while [[ $# -gt 0 ]]; do
    case $1 in
        --clone-dir) CLONE_DIR="$2"; shift 2 ;;
        --stack) STACK="$2"; shift 2 ;;
        --image) IMAGE="$2"; shift 2 ;;
        --cpu) CPU="$2"; shift 2 ;;
        --memory) MEMORY="$2"; shift 2 ;;
        --base) BASE_BRANCH="$2"; shift 2 ;;
        --fork) FORK=true; shift ;;
        -h|--help) usage 0 ;;
        -*)
            echo "Unknown option: $1"
            usage 1
            ;;
        *)
            if [ -z "$REPO" ]; then
                REPO="$1"
            elif [ -z "$BRANCH" ]; then
                BRANCH="$1"
            fi
            shift
            ;;
    esac
done

if [ -z "$REPO" ] || [ -z "$BRANCH" ]; then
    echo "Error: GitHub repo and branch are required"
    usage 1
fi

# Check gh is installed and authenticated
if ! command -v gh &> /dev/null; then
    echo "Error: GitHub CLI (gh) is not installed"
    echo "Install with: sudo apt install gh  # or brew install gh"
    exit 1
fi

if ! gh auth status &> /dev/null; then
    echo "Error: Not authenticated with GitHub"
    echo "Run: gh auth login"
    exit 1
fi

# Extract repo name
REPO_NAME="${REPO##*/}"
REPO_PATH="$CLONE_DIR/$REPO_NAME"

echo "=== GitHub Worktree Environment ==="
echo "  Repository: $REPO"
echo "  Branch:     $BRANCH"
echo "  Local path: $REPO_PATH"
echo

# Fork if requested
if [ "$FORK" = true ]; then
    echo "[1/4] Forking repository..."
    gh repo fork "$REPO" --clone=false 2>/dev/null || echo "  (fork may already exist)"

    # Update repo to point to fork
    GH_USER=$(gh api user --jq '.login')
    REPO="$GH_USER/$REPO_NAME"
    echo "  Will clone from fork: $REPO"
fi

# Clone if not exists
if [ ! -d "$REPO_PATH" ]; then
    echo "[2/4] Cloning repository..."
    mkdir -p "$CLONE_DIR"
    gh repo clone "$REPO" "$REPO_PATH"

    # If forked, add upstream remote
    if [ "$FORK" = true ]; then
        ORIGINAL_REPO="${REPO##*/}"
        cd "$REPO_PATH"
        # gh clone already sets up upstream for forks
        echo "  Upstream remote configured"
    fi
else
    echo "[2/4] Repository already cloned at $REPO_PATH"

    # Fetch latest
    echo "  Fetching latest..."
    cd "$REPO_PATH"
    git fetch --all --prune
fi

# Auto-detect stack if not specified
if [ -z "$STACK" ]; then
    echo "[3/4] Auto-detecting project stack..."
    cd "$REPO_PATH"

    if [ -f "package.json" ]; then
        STACK="nodejs"
    elif [ -f "pyproject.toml" ] || [ -f "setup.py" ] || [ -f "requirements.txt" ]; then
        STACK="python"
    elif [ -f "Cargo.toml" ]; then
        STACK="rust"
    elif [ -f "go.mod" ]; then
        STACK="go"
    else
        STACK="nodejs"  # default fallback
    fi
    echo "  Detected: $STACK"
else
    echo "[3/4] Using specified stack: $STACK"
fi

# Create worktree environment
echo "[4/4] Creating worktree environment..."
WORKTREE_ARGS=("$REPO_PATH" "$BRANCH" --stack "$STACK" --cpu "$CPU" --memory "$MEMORY" --base "$BASE_BRANCH")
[ -n "$IMAGE" ] && WORKTREE_ARGS+=(--image "$IMAGE")
"$SCRIPT_DIR/worktree-env.sh" "${WORKTREE_ARGS[@]}"
