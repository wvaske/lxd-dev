#!/bin/bash
# Create a git worktree and spin up a container for it
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

usage() {
    cat << EOF
Usage: $(basename "$0") <repo-path> <branch> [options]

Create a git worktree and spin up an LXD container with it mounted.

Arguments:
  repo-path         Path to the main git repository
  branch            Branch name for the worktree (created if doesn't exist)

Options:
  --name NAME       Container name (default: derived from branch name)
  --stack STACK     Development stack: nodejs, python, rust, go (default: nodejs)
  --image IMAGE     Base image (default: cdev-<stack> if exists, else ubuntu-base)
  --worktree-dir D  Directory for worktrees (default: <repo>/../worktrees)
  --cpu CORES       CPU limit (default: 4)
  --memory SIZE     Memory limit (default: 8GB)
  --base BRANCH     Base branch when creating new branch (default: main)
  --mount-path P    Mount path inside container (default: /home/developer/workspace/<repo-name>)
  --list            List existing worktree environments for a repo
  --destroy         Destroy container and remove worktree
  -h, --help        Show this help message

Examples:
  # Create worktree for existing branch
  $(basename "$0") ~/code/myapp feature/auth --stack nodejs

  # Create worktree for new branch based on main
  $(basename "$0") ~/code/myapp feature/new-api --base main

  # Create with custom name and resources
  $(basename "$0") ~/code/myapp bugfix/123 --name fix-123 --memory 16GB

  # List all worktree environments for a repo
  $(basename "$0") ~/code/myapp --list

  # Destroy a worktree environment
  $(basename "$0") ~/code/myapp feature/auth --destroy

Workflow:
  1. Creates git worktree at <worktree-dir>/<branch-name>
  2. Launches LXD container with worktree bind-mounted
  3. Work in container: changes appear in worktree immediately
  4. Commit/push from container or host - both see the same files
EOF
    exit "${1:-0}"
}

# Defaults
STACK="nodejs"
IMAGE=""
CPU="4"
MEMORY="8GB"
WORKTREE_DIR=""
CONTAINER_NAME=""
BASE_BRANCH="main"
MOUNT_PATH=""
ACTION="create"

# Parse arguments
REPO_PATH=""
BRANCH=""

while [[ $# -gt 0 ]]; do
    case $1 in
        --name) CONTAINER_NAME="$2"; shift 2 ;;
        --stack) STACK="$2"; shift 2 ;;
        --image) IMAGE="$2"; shift 2 ;;
        --worktree-dir) WORKTREE_DIR="$2"; shift 2 ;;
        --cpu) CPU="$2"; shift 2 ;;
        --memory) MEMORY="$2"; shift 2 ;;
        --base) BASE_BRANCH="$2"; shift 2 ;;
        --mount-path) MOUNT_PATH="$2"; shift 2 ;;
        --list) ACTION="list"; shift ;;
        --destroy) ACTION="destroy"; shift ;;
        -h|--help) usage 0 ;;
        -*)
            echo "Unknown option: $1"
            usage 1
            ;;
        *)
            if [ -z "$REPO_PATH" ]; then
                REPO_PATH="$1"
            elif [ -z "$BRANCH" ]; then
                BRANCH="$1"
            fi
            shift
            ;;
    esac
done

# Validate repo path
if [ -z "$REPO_PATH" ]; then
    echo "Error: Repository path is required"
    usage 1
fi

REPO_PATH="$(realpath "$REPO_PATH")"

if [ ! -d "$REPO_PATH/.git" ] && [ ! -f "$REPO_PATH/.git" ]; then
    echo "Error: '$REPO_PATH' is not a git repository"
    exit 1
fi

REPO_NAME="$(basename "$REPO_PATH")"

# Set defaults based on repo
if [ -z "$WORKTREE_DIR" ]; then
    WORKTREE_DIR="$(dirname "$REPO_PATH")/worktrees"
fi

# Handle list action
if [ "$ACTION" = "list" ]; then
    echo "Worktree environments for: $REPO_PATH"
    echo "============================================"
    echo

    # Get all worktrees
    cd "$REPO_PATH"
    echo "Git Worktrees:"
    git worktree list
    echo

    # Find associated containers
    echo "Associated Containers:"
    echo "NAME                 STATE    WORKTREE"
    echo "----                 -----    --------"

    for wt_path in $(git worktree list --porcelain | grep "^worktree " | cut -d' ' -f2-); do
        wt_name=$(basename "$wt_path")
        # Check for containers that mount this worktree
        for container in $(lxc list --format csv -c n); do
            mount_source=$(lxc config device get "$container" project source 2>/dev/null || true)
            if [ "$mount_source" = "$wt_path" ]; then
                state=$(lxc list "$container" --format csv -c s)
                printf "%-20s %-8s %s\n" "$container" "$state" "$wt_path"
            fi
        done
    done

    exit 0
fi

# Validate branch for create/destroy
if [ -z "$BRANCH" ]; then
    echo "Error: Branch name is required"
    usage 1
fi

# Sanitize branch name for use in paths and container names
BRANCH_SANITIZED="${BRANCH//\//-}"  # Replace / with -
BRANCH_SANITIZED="${BRANCH_SANITIZED//[^a-zA-Z0-9-]/-}"  # Replace other special chars with -

# Sanitize repo name for container names (LXD only allows alphanumeric and hyphens)
REPO_NAME_SANITIZED="${REPO_NAME//[^a-zA-Z0-9-]/-}"

# Set container name if not specified
if [ -z "$CONTAINER_NAME" ]; then
    CONTAINER_NAME="${REPO_NAME_SANITIZED}-${BRANCH_SANITIZED}"
fi

WORKTREE_PATH="$WORKTREE_DIR/$BRANCH_SANITIZED"

# Set mount path if not specified
if [ -z "$MOUNT_PATH" ]; then
    MOUNT_PATH="/home/developer/workspace/$REPO_NAME"
fi

# Handle destroy action
if [ "$ACTION" = "destroy" ]; then
    echo "Destroying worktree environment: $CONTAINER_NAME"
    echo "  Worktree: $WORKTREE_PATH"
    echo

    read -p "Are you sure? This will delete the container and worktree. [y/N] " -n 1 -r
    echo

    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo "Cancelled"
        exit 0
    fi

    # Stop and delete container
    if lxc info "$CONTAINER_NAME" &> /dev/null; then
        echo "Deleting container..."
        lxc delete "$CONTAINER_NAME" --force
    fi

    # Remove worktree
    if [ -d "$WORKTREE_PATH" ]; then
        echo "Removing worktree..."
        cd "$REPO_PATH"
        git worktree remove "$WORKTREE_PATH" --force 2>/dev/null || rm -rf "$WORKTREE_PATH"
    fi

    echo "Done"
    exit 0
fi

# === Create action ===

echo "=== Creating Worktree Environment ==="
echo "  Repository:  $REPO_PATH"
echo "  Branch:      $BRANCH"
echo "  Worktree:    $WORKTREE_PATH"
echo "  Container:   $CONTAINER_NAME"
echo "  Stack:       $STACK"
echo "  Mount path:  $MOUNT_PATH"
echo

# Check if container already exists
if lxc info "$CONTAINER_NAME" &> /dev/null; then
    echo "Error: Container '$CONTAINER_NAME' already exists"
    echo "  To enter: ./scripts/enter.sh $CONTAINER_NAME"
    echo "  To destroy: $(basename "$0") $REPO_PATH $BRANCH --destroy"
    exit 1
fi

# Create worktree directory
mkdir -p "$WORKTREE_DIR"

# Check if worktree already exists
if [ -d "$WORKTREE_PATH" ]; then
    echo "Worktree already exists at: $WORKTREE_PATH"
else
    echo "[1/4] Creating git worktree..."
    cd "$REPO_PATH"

    # Check if branch exists (local, origin, or upstream)
    if git show-ref --verify --quiet "refs/heads/$BRANCH"; then
        # Branch exists locally - use it directly
        echo "  Using local branch: $BRANCH"
        git worktree add "$WORKTREE_PATH" "$BRANCH"
    elif git show-ref --verify --quiet "refs/remotes/origin/$BRANCH"; then
        # Branch exists on origin - create local tracking branch
        echo "  Creating local branch tracking origin/$BRANCH"
        git worktree add -b "$BRANCH" "$WORKTREE_PATH" "origin/$BRANCH"
    elif git show-ref --verify --quiet "refs/remotes/upstream/$BRANCH"; then
        # Branch exists on upstream - create local branch from it
        echo "  Creating local branch from upstream/$BRANCH"
        git worktree add -b "$BRANCH" "$WORKTREE_PATH" "upstream/$BRANCH"
    else
        # Check any other remotes
        REMOTE_REF=$(git for-each-ref --format='%(refname:short)' "refs/remotes/*/$BRANCH" | head -1)
        if [ -n "$REMOTE_REF" ]; then
            echo "  Creating local branch from $REMOTE_REF"
            git worktree add -b "$BRANCH" "$WORKTREE_PATH" "$REMOTE_REF"
        else
            # Create new branch from base
            echo "  Branch '$BRANCH' doesn't exist, creating from '$BASE_BRANCH'..."
            git worktree add -b "$BRANCH" "$WORKTREE_PATH" "$BASE_BRANCH"
        fi
    fi
fi

echo "[2/4] Creating LXD container..."

# Auto-detect image if not specified
if [ -z "$IMAGE" ]; then
    # Check if custom image exists for this stack
    if lxc image info "cdev-${STACK}" &>/dev/null; then
        IMAGE="cdev-${STACK}"
        echo "  Using custom image: $IMAGE"
    else
        IMAGE="ubuntu-base"
        echo "  Using base image: $IMAGE (build 'cdev-${STACK}' for faster startup)"
    fi
fi

# Verify image exists
if ! lxc image info "$IMAGE" &>/dev/null; then
    echo "Error: Image '$IMAGE' not found"
    echo "Run 'cdev images' to see available images"
    echo "Run 'cdev build $STACK' to create a custom image"
    exit 1
fi

# Determine which profiles to apply
# Custom images (cdev-*) already have stack packages, so skip stack profile
if [[ "$IMAGE" == "ubuntu-base" ]]; then
    lxc launch "$IMAGE" "$CONTAINER_NAME" \
        --profile default \
        --profile claude-dev \
        --profile "$STACK" \
        --config "limits.cpu=$CPU" \
        --config "limits.memory=$MEMORY"
else
    lxc launch "$IMAGE" "$CONTAINER_NAME" \
        --profile default \
        --profile claude-dev \
        --config "limits.cpu=$CPU" \
        --config "limits.memory=$MEMORY"
fi

echo "[3/4] Mounting worktree into container..."

# Add the worktree as a disk device
lxc config device add "$CONTAINER_NAME" project disk \
    source="$WORKTREE_PATH" \
    path="$MOUNT_PATH"

# Worktrees have a .git file that points to main repo's .git directory
# Mount the main repo's .git directory at the same host path so git commands work
# The .git file contains absolute path like: gitdir: /home/user/repo/.git/worktrees/branch
lxc config device add "$CONTAINER_NAME" git-objects disk \
    source="$REPO_PATH/.git" \
    path="$REPO_PATH/.git" \
    readonly="false"

echo "[4/4] Configuring container..."

# Wait for container to be ready
sleep 2

# Set up user and permissions (ignore errors from read-only mounts)
lxc exec "$CONTAINER_NAME" --env "MOUNT_PATH=$MOUNT_PATH" --env "REPO_PATH=$REPO_PATH" -- bash -c '
    # Ensure developer user exists
    if ! id developer &>/dev/null; then
        useradd -m -s /bin/bash -G sudo developer
        echo "developer ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/developer
    fi

    # Create workspace directory structure
    mkdir -p /home/developer/workspace
    chown developer:developer /home/developer/workspace

    # Fix ownership of mounted project (match container user)
    chown -R developer:developer "$MOUNT_PATH" 2>/dev/null || true

    # Set up SSH keys
    mkdir -p /home/developer/.ssh
    if [ -d /home/developer/.ssh-host ]; then
        cp /home/developer/.ssh-host/id_* /home/developer/.ssh/ 2>/dev/null || true
        cp /home/developer/.ssh-host/known_hosts /home/developer/.ssh/ 2>/dev/null || true
        chmod 700 /home/developer/.ssh
        chmod 600 /home/developer/.ssh/id_* 2>/dev/null || true
    fi
    chown -R developer:developer /home/developer 2>/dev/null || true
    exit 0
'

# Copy .gitconfig from host if it exists (not mounted, so container can modify it)
if [ -f "$HOME/.gitconfig" ]; then
    lxc file push "$HOME/.gitconfig" "$CONTAINER_NAME/home/developer/.gitconfig" || true
    lxc exec "$CONTAINER_NAME" -- chown developer:developer /home/developer/.gitconfig 2>/dev/null || true
fi

# Configure git safe.directory for mounted paths (needed due to UID mapping)
lxc exec "$CONTAINER_NAME" -- su - developer -c "git config --global --add safe.directory '$MOUNT_PATH'" 2>/dev/null || true
lxc exec "$CONTAINER_NAME" -- su - developer -c "git config --global --add safe.directory '$REPO_PATH'" 2>/dev/null || true

# Ensure .profile exists (needed for login shells to source .bashrc)
lxc exec "$CONTAINER_NAME" -- bash -c '
    if [[ ! -f /home/developer/.profile ]]; then
        cp /etc/skel/.profile /home/developer/.profile
        chown developer:developer /home/developer/.profile
    fi
' 2>/dev/null || true

# Add shell customization (colored prompt, aliases, etc.)
if [ -f "$PROJECT_DIR/templates/bashrc-cdev.sh" ]; then
    lxc file push "$PROJECT_DIR/templates/bashrc-cdev.sh" "$CONTAINER_NAME/tmp/bashrc-cdev.sh" 2>/dev/null || true
    lxc exec "$CONTAINER_NAME" -- bash -c 'cat /tmp/bashrc-cdev.sh >> /home/developer/.bashrc && chown developer:developer /home/developer/.bashrc && rm /tmp/bashrc-cdev.sh' 2>/dev/null || true
fi

# Create snapshot
lxc snapshot "$CONTAINER_NAME" fresh

echo
echo "=== Worktree Environment Ready ==="
echo
echo "Container: $CONTAINER_NAME"
echo "Worktree:  $WORKTREE_PATH"
echo "Mounted:   $MOUNT_PATH"
echo
echo "Commands:"
echo "  Enter:     ./scripts/enter.sh $CONTAINER_NAME"
echo "  VS Code:   ./scripts/vscode-connect.sh $CONTAINER_NAME --folder $MOUNT_PATH"
echo "  Destroy:   $(basename "$0") $REPO_PATH $BRANCH --destroy"
echo
echo "The worktree is bind-mounted, so:"
echo "  - Changes in container appear on host immediately"
echo "  - You can commit/push from either host or container"
echo "  - Git history is shared with main repo"
