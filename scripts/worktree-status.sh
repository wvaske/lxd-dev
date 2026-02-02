#!/bin/bash
# Show status of all worktree environments for a repository
set -euo pipefail

usage() {
    cat << EOF
Usage: $(basename "$0") <repo-path> [options]

Show status of all worktree environments for a repository.

Arguments:
  repo-path         Path to the main git repository

Options:
  --exec CMD        Run command in all running worktree containers
  --start-all       Start all stopped worktree containers
  --stop-all        Stop all running worktree containers
  -h, --help        Show this help message

Examples:
  $(basename "$0") ~/code/myapp
  $(basename "$0") ~/code/myapp --exec "git status"
  $(basename "$0") ~/code/myapp --exec "git pull origin main"
  $(basename "$0") ~/code/myapp --stop-all
EOF
    exit "${1:-0}"
}

# Parse arguments
REPO_PATH=""
EXEC_CMD=""
ACTION="status"

while [[ $# -gt 0 ]]; do
    case $1 in
        --exec) EXEC_CMD="$2"; ACTION="exec"; shift 2 ;;
        --start-all) ACTION="start"; shift ;;
        --stop-all) ACTION="stop"; shift ;;
        -h|--help) usage 0 ;;
        -*) echo "Unknown option: $1"; usage 1 ;;
        *) REPO_PATH="$1"; shift ;;
    esac
done

if [ -z "$REPO_PATH" ]; then
    echo "Error: Repository path is required"
    usage 1
fi

REPO_PATH="$(realpath "$REPO_PATH")"
REPO_NAME="$(basename "$REPO_PATH")"

if [ ! -d "$REPO_PATH/.git" ] && [ ! -f "$REPO_PATH/.git" ]; then
    echo "Error: '$REPO_PATH' is not a git repository"
    exit 1
fi

cd "$REPO_PATH"

# Build list of worktrees and their associated containers
declare -A WORKTREE_CONTAINERS

echo "Repository: $REPO_PATH"
echo "============================================"
echo

# Get all worktrees
while IFS= read -r line; do
    if [[ "$line" == worktree* ]]; then
        wt_path="${line#worktree }"
        wt_name=$(basename "$wt_path")

        # Find container that mounts this worktree
        container=""
        for c in $(lxc list --format csv -c n 2>/dev/null); do
            mount_source=$(lxc config device get "$c" project source 2>/dev/null || true)
            if [ "$mount_source" = "$wt_path" ]; then
                container="$c"
                break
            fi
        done

        WORKTREE_CONTAINERS["$wt_path"]="$container"
    fi
done < <(git worktree list --porcelain)

case "$ACTION" in
    status)
        printf "%-30s %-20s %-10s %-15s %s\n" "BRANCH" "CONTAINER" "STATE" "IP" "WORKTREE"
        printf "%-30s %-20s %-10s %-15s %s\n" "------" "---------" "-----" "--" "--------"

        for wt_path in "${!WORKTREE_CONTAINERS[@]}"; do
            container="${WORKTREE_CONTAINERS[$wt_path]}"
            wt_name=$(basename "$wt_path")

            # Get branch name
            branch=$(git -C "$wt_path" branch --show-current 2>/dev/null || echo "detached")

            if [ -n "$container" ]; then
                state=$(lxc list "$container" --format csv -c s 2>/dev/null || echo "?")
                ip=$(lxc list "$container" --format csv -c 4 2>/dev/null | cut -d' ' -f1)
                [ -z "$ip" ] && ip="-"
            else
                state="-"
                ip="-"
                container="-"
            fi

            printf "%-30s %-20s %-10s %-15s %s\n" "$branch" "$container" "$state" "$ip" "$wt_path"
        done
        ;;

    exec)
        echo "Executing in all running containers: $EXEC_CMD"
        echo

        for wt_path in "${!WORKTREE_CONTAINERS[@]}"; do
            container="${WORKTREE_CONTAINERS[$wt_path]}"

            if [ -z "$container" ]; then
                continue
            fi

            state=$(lxc list "$container" --format csv -c s 2>/dev/null || echo "STOPPED")

            if [ "$state" = "RUNNING" ]; then
                branch=$(git -C "$wt_path" branch --show-current 2>/dev/null || echo "?")
                echo "=== $container ($branch) ==="

                # Get mount path
                mount_path=$(lxc config device get "$container" project path 2>/dev/null || echo "/home/developer/workspace")

                lxc exec "$container" -- su - developer -c "cd '$mount_path' && $EXEC_CMD" 2>&1 || true
                echo
            fi
        done
        ;;

    start)
        echo "Starting all stopped containers..."

        for wt_path in "${!WORKTREE_CONTAINERS[@]}"; do
            container="${WORKTREE_CONTAINERS[$wt_path]}"

            if [ -z "$container" ]; then
                continue
            fi

            state=$(lxc list "$container" --format csv -c s 2>/dev/null || echo "?")

            if [ "$state" = "STOPPED" ]; then
                echo "  Starting: $container"
                lxc start "$container"
            fi
        done

        echo "Done"
        ;;

    stop)
        echo "Stopping all running containers..."

        for wt_path in "${!WORKTREE_CONTAINERS[@]}"; do
            container="${WORKTREE_CONTAINERS[$wt_path]}"

            if [ -z "$container" ]; then
                continue
            fi

            state=$(lxc list "$container" --format csv -c s 2>/dev/null || echo "?")

            if [ "$state" = "RUNNING" ]; then
                echo "  Stopping: $container"
                lxc stop "$container"
            fi
        done

        echo "Done"
        ;;
esac
