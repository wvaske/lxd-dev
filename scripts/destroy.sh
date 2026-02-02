#!/bin/bash
# Destroy a Claude Code development container
set -euo pipefail

usage() {
    cat << EOF
Usage: $(basename "$0") <name> [options]

Destroy a Claude Code development container and all its snapshots.

Arguments:
  name              Name of the container (required)

Options:
  --force           Skip confirmation prompt
  --keep-snapshots  Export snapshots before destroying
  -h, --help        Show this help message

Examples:
  $(basename "$0") my-project
  $(basename "$0") my-project --force
EOF
    exit "${1:-0}"
}

# Defaults
FORCE=false
KEEP_SNAPSHOTS=false

# Parse arguments
NAME=""
while [[ $# -gt 0 ]]; do
    case $1 in
        --force) FORCE=true; shift ;;
        --keep-snapshots) KEEP_SNAPSHOTS=true; shift ;;
        -h|--help) usage 0 ;;
        -*) echo "Unknown option: $1"; usage 1 ;;
        *) NAME="$1"; shift ;;
    esac
done

if [ -z "$NAME" ]; then
    echo "Error: Container name is required"
    usage 1
fi

# Check if container exists
if ! lxc info "$NAME" &> /dev/null; then
    echo "Error: Container '$NAME' does not exist"
    exit 1
fi

# Show container info
echo "Container: $NAME"
echo
lxc info "$NAME" | grep -E "^(Status|Created|Profiles|Snapshots):" | head -10
echo

# List snapshots
SNAPSHOTS=$(lxc info "$NAME" | grep -A 100 "^Snapshots:" | tail -n +2 | grep -v "^$" | head -10)
if [ -n "$SNAPSHOTS" ]; then
    echo "Snapshots that will be deleted:"
    echo "$SNAPSHOTS"
    echo
fi

if [ "$FORCE" = false ]; then
    echo "WARNING: This will permanently delete the container and all snapshots."
    read -p "Are you sure you want to destroy '$NAME'? [y/N] " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo "Destroy cancelled"
        exit 0
    fi
fi

# Export snapshots if requested
if [ "$KEEP_SNAPSHOTS" = true ] && [ -n "$SNAPSHOTS" ]; then
    EXPORT_DIR="./exports/${NAME}-$(date +%Y%m%d-%H%M%S)"
    mkdir -p "$EXPORT_DIR"
    echo "Exporting snapshots to $EXPORT_DIR..."

    lxc info "$NAME" | grep -A 100 "^Snapshots:" | tail -n +2 | while read -r snap_line; do
        snap_name=$(echo "$snap_line" | awk '{print $1}')
        if [ -n "$snap_name" ] && [ "$snap_name" != "-" ]; then
            echo "  Exporting: $snap_name"
            lxc export "$NAME/$snap_name" "$EXPORT_DIR/${snap_name}.tar.gz" --optimized-storage
        fi
    done
fi

# Stop container if running
STATE=$(lxc list "$NAME" --format csv -c s)
if [ "$STATE" = "RUNNING" ]; then
    echo "Stopping container..."
    lxc stop "$NAME" --force
fi

# Delete container
echo "Deleting container '$NAME'..."
lxc delete "$NAME" --force

echo
echo "Container '$NAME' has been destroyed."
