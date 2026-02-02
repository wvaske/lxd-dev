#!/bin/bash
# One-time setup script for LXD Claude Code development environments
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

echo "=== LXD Claude Code Environment Setup ==="
echo

# Check if LXD is installed
if ! command -v lxc &> /dev/null; then
    echo "Error: LXD is not installed. Install with:"
    echo "  sudo snap install lxd"
    echo "  sudo lxd init"
    exit 1
fi

# Check if LXD is initialized
if ! lxc storage list &> /dev/null; then
    echo "Error: LXD is not initialized. Run: sudo lxd init"
    exit 1
fi

echo "[1/5] Creating base profile: claude-dev"
# Expand environment variables in profile (LXD doesn't do this)
PROFILE_TEMP=$(mktemp)
envsubst < "$PROJECT_DIR/profiles/claude-dev.yaml" > "$PROFILE_TEMP"

# Remove gitconfig device if file doesn't exist
if [ ! -f "$HOME/.gitconfig" ]; then
    echo "  Note: ~/.gitconfig not found, skipping gitconfig mount"
    sed -i '/gitconfig:/,/type: disk/d' "$PROFILE_TEMP"
fi

if lxc profile show claude-dev &> /dev/null; then
    echo "  Profile exists, updating..."
    lxc profile edit claude-dev < "$PROFILE_TEMP"
else
    lxc profile create claude-dev
    lxc profile edit claude-dev < "$PROFILE_TEMP"
fi
rm -f "$PROFILE_TEMP"

echo "[2/5] Creating stack profiles..."
for stack in nodejs python rust go; do
    profile_file="$PROJECT_DIR/profiles/stacks/${stack}.yaml"
    if [ -f "$profile_file" ]; then
        if lxc profile show "$stack" &> /dev/null; then
            echo "  Updating profile: $stack"
            lxc profile edit "$stack" < "$profile_file"
        else
            echo "  Creating profile: $stack"
            lxc profile create "$stack"
            lxc profile edit "$stack" < "$profile_file"
        fi
    fi
done

echo "[3/5] Preparing cloud-init configurations..."
# Merge cloud-init files and inject SSH keys
SSH_KEYS=""
for key_file in ~/.ssh/id_*.pub; do
    if [ -f "$key_file" ]; then
        SSH_KEYS+="      - $(cat "$key_file")"$'\n'
    fi
done

# Create merged cloud-init
MERGED_CLOUD_INIT="$PROJECT_DIR/.cache/cloud-init-merged.yaml"
mkdir -p "$(dirname "$MERGED_CLOUD_INIT")"

cat "$PROJECT_DIR/cloud-init/base.yaml" > "$MERGED_CLOUD_INIT"
echo "" >> "$MERGED_CLOUD_INIT"
cat "$PROJECT_DIR/cloud-init/claude-code.yaml" >> "$MERGED_CLOUD_INIT"

# Inject SSH keys
if [ -n "$SSH_KEYS" ]; then
    sed -i "s|ssh_authorized_keys: \[\]|ssh_authorized_keys:\n$SSH_KEYS|" "$MERGED_CLOUD_INIT"
fi

echo "[4/5] Downloading base image (ubuntu:24.04)..."
lxc image copy ubuntu:24.04 local: --alias ubuntu-base --auto-update 2>/dev/null || echo "  (image may already exist)"

echo "[5/5] Setting up PATH..."
# Remove old aliases if present (from previous versions)
ALIAS_FILE="$HOME/.bash_aliases"
if grep -q "claude-dev aliases" "$ALIAS_FILE" 2>/dev/null; then
    # Remove old alias block
    sed -i '/# claude-dev aliases/,/^$/d' "$ALIAS_FILE"
    echo "  Removed old aliases from $ALIAS_FILE"
fi

# Add to PATH via .bashrc if not already present
BASHRC="$HOME/.bashrc"
if ! grep -q "lxd-dev/cdev" "$BASHRC" 2>/dev/null; then
    cat >> "$BASHRC" << EOF

# cdev - Claude Code Development Environments
export PATH="$PROJECT_DIR:\$PATH"
EOF
    echo "  Added cdev to PATH in $BASHRC"
    echo "  Run 'source ~/.bashrc' or start a new shell to use 'cdev' command"
else
    echo "  PATH already configured"
fi

echo
echo "=== Setup Complete ==="
echo
echo "Usage:"
echo "  ./scripts/create-env.sh <name> --stack <nodejs|python|rust|go>"
echo "  ./scripts/enter.sh <name>"
echo "  ./scripts/list.sh"
echo "  ./scripts/snapshot.sh <name> <snapshot-name>"
echo "  ./scripts/destroy.sh <name>"
echo
echo "Or use aliases: cdev, cdev-enter, cdev-list, cdev-snap, cdev-destroy"
