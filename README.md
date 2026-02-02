# cdev - Claude Code Development Environments

Sandboxed LXD containers for running Claude Code safely, with git worktree support for parallel development.

## Quick Start

```bash
# One-time setup
./cdev setup

# Create a container
./cdev create my-project --stack python

# Enter and work
./cdev enter my-project
# Inside: git clone ..., cd repo, claude

# Snapshot before risky changes
./cdev snapshot my-project save before-refactor
```

## Parallel Branch Development

Work on multiple branches simultaneously, each in isolated containers:

```bash
# Create worktree environments from GitHub
./cdev worktree wvaske/dlio_benchmark feature/auth --stack python
./cdev worktree wvaske/dlio_benchmark bugfix/123 --stack python

# Check status
./cdev status ~/Projects/dlio_benchmark

# Run commands across all containers
./cdev status ~/Projects/dlio_benchmark --exec "git pull origin main"
./cdev status ~/Projects/dlio_benchmark --exec "pytest"

# Stop all when done
./cdev status ~/Projects/dlio_benchmark --stop-all
```

## Installation

```bash
# Install LXD
sudo snap install lxd
sudo lxd init --auto
sudo usermod -aG lxd $USER
newgrp lxd  # or logout/login

# Clone this repo
git clone <repo-url> ~/lxd-dev
cd ~/lxd-dev

# Run setup (adds cdev to PATH and enables tab completion)
./cdev setup

# Activate in current shell
source ~/.bashrc
```

Setup automatically configures:
- `cdev` command in your PATH
- Tab completion for commands, containers, and options

## Commands

| Command | Description |
|---------|-------------|
| `cdev setup` | One-time LXD profile and image setup |
| `cdev create <name>` | Create standalone dev container |
| `cdev worktree <repo> <branch>` | Create container + git worktree |
| `cdev enter <name>` | Enter container shell |
| `cdev list` | List all containers |
| `cdev status <repo>` | Show worktree environments |
| `cdev snapshot <name> <action>` | Manage snapshots |
| `cdev vscode <name>` | Connect VS Code Remote-SSH |
| `cdev exec <name> <cmd>` | Run command in container |
| `cdev destroy <name>` | Remove container |

Run `cdev <command> --help` for detailed options.

## Workflows

### Standalone Container

For working on a single project:

```bash
# Create
./cdev create api-server --stack nodejs --memory 16GB

# Enter and clone
./cdev enter api-server
git clone git@github.com:myorg/api.git
cd api && npm install
claude

# Snapshot before experiments
./cdev snapshot api-server save pre-refactor

# Restore if needed
./cdev snapshot api-server restore pre-refactor

# Clean up
./cdev destroy api-server
```

### Parallel Worktrees (from GitHub)

For working on multiple branches simultaneously:

```bash
# First branch
./cdev worktree myorg/myrepo feature/auth --stack python

# Second branch (creates worktree, reuses cloned repo)
./cdev worktree myorg/myrepo feature/api --stack python

# Work in parallel (separate terminals)
./cdev enter myrepo-feature-auth
./cdev enter myrepo-feature-api

# Or open in VS Code
./cdev vscode myrepo-feature-auth

# Run tests across all
./cdev status ~/Projects/myrepo --exec "pytest"

# Clean up one branch
./cdev worktree ~/Projects/myrepo feature/auth --destroy
```

### Parallel Worktrees (from local repo)

```bash
# From existing local clone
./cdev worktree ~/code/myapp feature/new-ui --stack nodejs
./cdev worktree ~/code/myapp bugfix/issue-42 --stack nodejs

# List all worktree environments
./cdev worktree ~/code/myapp --list
```

## Architecture

```
Host System
├── ~/Projects/myrepo/              # Main clone (main branch)
│   └── .git/
├── ~/Projects/worktrees/
│   ├── feature-auth/               # Worktree (feature/auth branch)
│   └── feature-api/                # Worktree (feature/api branch)
│
└── LXD Containers
    ├── myrepo-feature-auth         # Container with worktree mounted
    │   └── /home/developer/workspace/myrepo → ~/Projects/worktrees/feature-auth
    └── myrepo-feature-api
        └── /home/developer/workspace/myrepo → ~/Projects/worktrees/feature-api
```

**Key points:**
- Worktrees share git objects (efficient storage)
- Bind mounts = instant sync (no push/pull needed)
- Commit/push from container or host
- Full container isolation (processes, resources)

## Available Stacks

| Stack | Includes |
|-------|----------|
| `nodejs` | Node.js LTS, npm, common build tools |
| `python` | Python 3.12, pip, venv |
| `rust` | Rust stable, cargo, common tools |
| `go` | Go 1.22+, common tools |

## Security Model

### Isolation Guarantees

| Aspect | Protection |
|--------|------------|
| Filesystem | Container has own root; SSH keys mounted read-only |
| Processes | Separate PID namespace |
| Network | Full access but isolated namespace |
| Users | Unprivileged container with UID mapping |
| Resources | CPU, memory, disk limits enforced |

### What Claude CAN Do (in container)

- Read/write container files
- Install packages
- Run commands as developer or root
- Make network requests
- Git operations via mounted SSH keys

### What Claude CANNOT Do

- Access host filesystem
- See/affect host processes
- Escape container
- Exceed resource limits

## Snapshots

Snapshots are essential for safe experimentation:

```bash
# Create before risky operation
./cdev snapshot my-project save before-experiment

# If things go wrong
./cdev snapshot my-project restore before-experiment

# List snapshots
./cdev snapshot my-project list

# Delete old snapshot
./cdev snapshot my-project delete old-snapshot
```

## VS Code Integration

Connect VS Code to containers via Remote-SSH:

```bash
# Prerequisites: Install "Remote - SSH" extension

# Connect VS Code
./cdev vscode my-project

# Open specific folder
./cdev vscode my-project --folder /home/developer/workspace/myrepo
```

## Configuration

### Resource Limits

Override defaults per container:

```bash
./cdev create ml-project --stack python --cpu 8 --memory 32GB
```

Or edit `profiles/claude-dev.yaml` for global defaults.

### GPU Passthrough

Uncomment in `profiles/claude-dev.yaml`:

```yaml
devices:
  gpu:
    type: gpu
    gid: "1000"
```

### Custom Stacks

Create `profiles/stacks/mystack.yaml`:

```yaml
config:
  user.user-data: |
    #cloud-config
    packages:
      - your-packages
    runcmd:
      - your-setup-commands
description: My custom stack
name: mystack
```

Then run `./cdev setup` to register.

## Troubleshooting

### "LXD socket not accessible"

```bash
sudo usermod -aG lxd $USER
newgrp lxd  # or logout/login
```

### Container won't start

```bash
lxc info <name> --show-log
systemctl status snap.lxd.daemon
```

### Git "dubious ownership" errors

The container setup should handle this automatically. If not:

```bash
./cdev enter <name>
git config --global --add safe.directory /home/developer/workspace/myrepo
```

### Can't connect via SSH

```bash
# Check container has IP
./cdev list

# Verify SSH is running
./cdev exec <name> --root systemctl status ssh
```

## Directory Structure

```
lxd-dev/
├── cdev                    # Main CLI entry point
├── completions/
│   └── cdev.bash           # Bash tab completion
├── scripts/                # Implementation scripts
│   ├── setup.sh
│   ├── create-env.sh
│   ├── worktree-env.sh
│   ├── gh-worktree-env.sh
│   ├── worktree-status.sh
│   ├── enter.sh
│   ├── snapshot.sh
│   ├── vscode-connect.sh
│   ├── destroy.sh
│   └── list.sh
├── profiles/
│   ├── claude-dev.yaml     # Base LXD profile
│   └── stacks/             # Stack-specific profiles
├── cloud-init/             # Container provisioning
└── README.md
```

## License

MIT
