#!/bin/bash
# Create a new Claude Code development container
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

usage() {
    cat << EOF
Usage: $(basename "$0") <name> [options]

Create a new sandboxed Claude Code development environment.

Arguments:
  name              Name for the container (required)

Options:
  --stack STACK     Development stack: nodejs, python, rust, go (default: nodejs)
  --cpu CORES       CPU limit (default: 4)
  --memory SIZE     Memory limit (default: 8GB)
  --disk SIZE       Disk limit (default: 50GB)
  --api-key KEY     Anthropic API key (or set ANTHROPIC_API_KEY env var)
  --no-start        Create but don't start the container
  -h, --help        Show this help message

Examples:
  $(basename "$0") my-project
  $(basename "$0") ml-work --stack python --memory 16GB
  $(basename "$0") web-app --stack nodejs --cpu 2
EOF
    exit "${1:-0}"
}

# Defaults
STACK="nodejs"
CPU="4"
MEMORY="8GB"
DISK="50GB"
START=true
API_KEY="${ANTHROPIC_API_KEY:-}"

# Parse arguments
NAME=""
while [[ $# -gt 0 ]]; do
    case $1 in
        --stack) STACK="$2"; shift 2 ;;
        --cpu) CPU="$2"; shift 2 ;;
        --memory) MEMORY="$2"; shift 2 ;;
        --disk) DISK="$2"; shift 2 ;;
        --api-key) API_KEY="$2"; shift 2 ;;
        --no-start) START=false; shift ;;
        -h|--help) usage 0 ;;
        -*) echo "Unknown option: $1"; usage 1 ;;
        *) NAME="$1"; shift ;;
    esac
done

if [ -z "$NAME" ]; then
    echo "Error: Container name is required"
    usage 1
fi

# Validate stack
if [[ ! "$STACK" =~ ^(nodejs|python|rust|go)$ ]]; then
    echo "Error: Invalid stack '$STACK'. Choose: nodejs, python, rust, go"
    exit 1
fi

# Check if container already exists
if lxc info "$NAME" &> /dev/null; then
    echo "Error: Container '$NAME' already exists"
    echo "  To enter: ./scripts/enter.sh $NAME"
    echo "  To delete: ./scripts/destroy.sh $NAME"
    exit 1
fi

echo "=== Creating Claude Code Environment: $NAME ==="
echo "  Stack:  $STACK"
echo "  CPU:    $CPU cores"
echo "  Memory: $MEMORY"
echo "  Disk:   $DISK"
echo

# Prepare cloud-init with API key
CLOUD_INIT_FILE="$PROJECT_DIR/.cache/cloud-init-merged.yaml"
if [ ! -f "$CLOUD_INIT_FILE" ]; then
    echo "Error: Run ./scripts/setup.sh first"
    exit 1
fi

TEMP_CLOUD_INIT=$(mktemp)
cp "$CLOUD_INIT_FILE" "$TEMP_CLOUD_INIT"

# Inject API key if provided
if [ -n "$API_KEY" ]; then
    # Add API key export to runcmd
    cat >> "$TEMP_CLOUD_INIT" << EOF

runcmd:
  - echo "export ANTHROPIC_API_KEY='$API_KEY'" >> /home/developer/.bashrc
EOF
fi

echo "[1/4] Launching container..."
lxc launch ubuntu-base "$NAME" \
    --profile default \
    --profile claude-dev \
    --profile "$STACK" \
    --config "limits.cpu=$CPU" \
    --config "limits.memory=$MEMORY"

echo "[2/4] Applying cloud-init configuration..."
lxc file push "$TEMP_CLOUD_INIT" "$NAME/etc/cloud/cloud.cfg.d/99-claude-dev.cfg"

# Apply disk limit to root device
lxc config device set "$NAME" root size="$DISK"

echo "[3/4] Waiting for cloud-init to complete..."
# Wait for container to be ready
sleep 2
lxc exec "$NAME" -- cloud-init status --wait 2>/dev/null || true

echo "[4/4] Running initial setup..."
# Ensure developer user exists and has correct permissions
lxc exec "$NAME" -- bash -c '
    # Create developer user if not exists
    if ! id developer &>/dev/null; then
        useradd -m -s /bin/bash -G sudo developer
        echo "developer ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/developer
    fi

    # Fix SSH directory
    mkdir -p /home/developer/.ssh
    chown -R developer:developer /home/developer

    # Create workspace
    mkdir -p /home/developer/workspace
    chown developer:developer /home/developer/workspace
'

# Copy SSH keys from host mount
lxc exec "$NAME" -- bash -c '
    if [ -d /home/developer/.ssh-host ]; then
        cp /home/developer/.ssh-host/id_* /home/developer/.ssh/ 2>/dev/null || true
        cp /home/developer/.ssh-host/known_hosts /home/developer/.ssh/ 2>/dev/null || true
        chown -R developer:developer /home/developer/.ssh
        chmod 700 /home/developer/.ssh
        chmod 600 /home/developer/.ssh/id_* 2>/dev/null || true
    fi
'

# Clean up
rm -f "$TEMP_CLOUD_INIT"

# Create initial snapshot
echo "Creating initial snapshot: 'fresh'..."
lxc snapshot "$NAME" fresh

echo
echo "=== Environment Ready: $NAME ==="
echo
echo "Commands:"
echo "  Enter container:    ./scripts/enter.sh $NAME"
echo "  Create snapshot:    ./scripts/snapshot.sh $NAME <name>"
echo "  Restore snapshot:   ./scripts/snapshot.sh $NAME --restore <name>"
echo "  Delete container:   ./scripts/destroy.sh $NAME"
echo
echo "Inside the container:"
echo "  cd ~/workspace"
echo "  git clone <your-repo>"
echo "  claude"
echo

if [ "$START" = true ]; then
    # Get container IP
    IP=$(lxc list "$NAME" --format csv -c 4 | cut -d' ' -f1)
    echo "Container IP: $IP"
    echo "SSH access:   ssh developer@$IP"
fi
