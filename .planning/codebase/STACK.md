# Technology Stack

**Analysis Date:** 2026-02-02

## Languages

**Primary:**
- Bash (5.x) - Entire codebase is shell scripts

**Secondary:**
- YAML - Configuration files (cloud-init, LXD profiles, stack configs)
- AWK - Inline YAML parsing in `scripts/lib/yaml-parser.sh`

## Runtime

**Environment:**
- Bash with `set -euo pipefail` strict mode
- Runs on Linux hosts with LXD/Incus installed
- Containers run Ubuntu 24.04

**Package Manager:**
- None (pure shell scripts, no package manifest)
- No lockfile

## Frameworks

**Core:**
- LXD (via `lxc` CLI) - Container management platform
- cloud-init - Container provisioning on first boot

**Build/Dev:**
- `envsubst` - Template variable expansion in `cdev` setup
- Custom YAML parser in `scripts/lib/yaml-parser.sh` (AWK-based)

## Key Dependencies

**Critical (host-level):**
- `lxc` / LXD - Core container management (installed via `snap install lxd`)
- `git` - Worktree management for parallel branch development
- `ssh` - Container access and VS Code Remote-SSH integration
- `gh` (GitHub CLI) - GitHub repo cloning in `scripts/gh-worktree-env.sh`

**Container-level (installed in images):**
- `@anthropic-ai/claude-code` (npm) - AI coding assistant, the primary tool containers are built for
- Node.js LTS + npm - Required for Claude Code installation
- `openssh-server` - SSH access into containers
- `gh` (GitHub CLI) - Installed via post-apt commands in `configs/base.yaml`

## Configuration

**Environment Variables:**
- `ANTHROPIC_API_KEY` - Required for Claude Code in containers (set in `cloud-init/claude-code.yaml`)
- `HOME` - Used for SSH key path expansion in `profiles/claude-dev.yaml`

**Config Files (project):**
- `configs/base.yaml` - Base packages for ALL container images
- `configs/stacks/{nodejs,python,rust,go}.yaml` - Stack-specific packages
- `profiles/claude-dev.yaml` - LXD profile with resource limits, device mounts
- `profiles/stacks/*.yaml` - Stack-specific LXD profiles (cloud-init)
- `cloud-init/base.yaml` - Base cloud-init (user creation, packages, SSH)
- `cloud-init/claude-code.yaml` - Claude Code installation cloud-init
- `templates/bashrc-cdev.sh` - Shell config pushed into containers
- `completions/cdev.bash` - Bash tab completion

**Container Defaults:**
- CPU: 4 cores
- Memory: 8GB
- Disk: 50GB
- User: `developer` (UID 1000) with passwordless sudo

## Platform Requirements

**Development/Host:**
- Linux (Ubuntu/Debian recommended)
- LXD installed and initialized (`snap install lxd && sudo lxd init --auto`)
- User in `lxd` group
- SSH keys at `~/.ssh/` (mounted read-only into containers)
- `envsubst` available (part of `gettext-base`)

**Container Images:**
- Ubuntu 24.04 base (`ubuntu:24.04` from LXD image server)
- Custom images built via `cdev build <stack>` and stored locally

## CLI Tool

**Entry Point:** `cdev` (version 1.0.0)
- Location: `cdev` (project root)
- ~1468 lines of Bash
- Subcommand pattern: `cdev <command> [options]`
- Commands delegate to scripts in `scripts/` directory

**Available Stacks:**

| Stack | Key Tools |
|-------|-----------|
| `nodejs` | Node.js LTS, typescript, ts-node, eslint, prettier |
| `python` | Python 3, pip, venv, black, ruff, mypy, pytest, ipython |
| `rust` | rustup, cargo, rustfmt, clippy |
| `go` | Go 1.22.0 |

---

*Stack analysis: 2026-02-02*
