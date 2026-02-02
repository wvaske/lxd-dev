# External Integrations

**Analysis Date:** 2026-02-02

## APIs & External Services

**Anthropic (Claude Code):**
- Claude Code AI assistant installed in every container
  - SDK/Client: `@anthropic-ai/claude-code` (npm global package)
  - Auth: `ANTHROPIC_API_KEY` env var set in container
  - Config: `/home/developer/.config/claude-code/config.json` inside container
  - Credential storage: `~/.claude/.credentials.json` or `~/.config/claude-code/credentials.json`

**GitHub:**
- GitHub CLI (`gh`) installed in containers via `configs/base.yaml`
  - Auth: `gh auth login` (interactive, browser-based)
  - Used for: repo cloning in `scripts/gh-worktree-env.sh`
  - Pattern: `cdev worktree owner/repo branch` triggers GitHub clone flow

**NodeSource:**
- Node.js LTS installation source
  - URL: `https://deb.nodesource.com/setup_lts.x`
  - Used in: `configs/stacks/nodejs.yaml`, `scripts/build-image.sh`

**Ubuntu LXD Image Server:**
- Base container images
  - Image: `ubuntu:24.04` aliased locally as `ubuntu-base`
  - Auto-update enabled on download

**Rust (rustup.rs):**
- Rust toolchain installer
  - URL: `https://sh.rustup.rs`
  - Used in: `configs/stacks/rust.yaml`

**Go (go.dev):**
- Go binary distribution
  - URL: `https://go.dev/dl/go1.22.0.linux-amd64.tar.gz`
  - Used in: `configs/stacks/go.yaml`

## Data Storage

**Databases:**
- None

**File Storage:**
- Local filesystem only
- LXD storage pool (`default`) for container root disks
- Git worktrees stored at `~/Projects/worktrees/` on host
- Container images stored in LXD local image store

**Caching:**
- `.cache/cloud-init-merged.yaml` - Merged cloud-init config generated during setup

## Authentication & Identity

**SSH Keys:**
- Host `~/.ssh/` mounted read-only at `/home/developer/.ssh-host/` in containers
  - Configured in: `profiles/claude-dev.yaml`
  - SSH config template: `cloud-init/base.yaml` (routes github.com/gitlab.com/bitbucket.org to host keys)

**Git Config:**
- Host `~/.gitconfig` copied (not mounted) into containers during build/refresh
  - Allows container to modify (e.g., `safe.directory`)
  - Refreshed via: `cdev refresh <container>`

**Container Access:**
- Primary: `lxc exec` (no SSH needed)
- Secondary: SSH via container IP (for VS Code Remote-SSH)
  - SSH configured in: `scripts/vscode-connect.sh`
  - User: `developer` (UID 1000, passwordless sudo)

## Monitoring & Observability

**Error Tracking:**
- None

**Logs:**
- LXD container logs: `lxc info <name> --show-log`
- cloud-init logs inside containers
- No structured logging in cdev scripts

## CI/CD & Deployment

**Hosting:**
- Local development tool only (not deployed to servers)

**CI Pipeline:**
- None

## Environment Configuration

**Required env vars (host):**
- None strictly required for `cdev` itself
- `HOME` - Used for SSH key path in LXD profile

**Required env vars (container):**
- `ANTHROPIC_API_KEY` - For Claude Code usage

**Secrets location:**
- SSH keys: Host `~/.ssh/` (mounted read-only)
- Claude Code credentials: Inside container at `~/.claude/` or `~/.config/claude-code/`
- GitHub CLI tokens: Inside container (managed by `gh auth`)

## LXD Integration Details

**Profiles:**
- `default` - LXD default profile (always applied)
- `claude-dev` - Base dev profile defined in `profiles/claude-dev.yaml`
- `nodejs`, `python`, `rust`, `go` - Stack profiles in `profiles/stacks/`

**LXD Features Used:**
- Container lifecycle: `lxc launch`, `lxc start`, `lxc stop`, `lxc delete`
- Snapshots: `lxc snapshot`, `lxc restore`
- File operations: `lxc file push`
- Command execution: `lxc exec`
- Proxy devices: Port forwarding via `lxc config device add` (proxy type)
- Disk devices: Bind mounts for worktrees and SSH keys
- Image management: `lxc image copy`, `lxc publish`
- Profile management: `lxc profile create`, `lxc profile edit`
- UID mapping: `raw.idmap` for UID 1000 passthrough
- Security nesting: Enabled for potential Docker-in-LXD

**Bind Mounts (per-container):**
- SSH keys: Host `~/.ssh` -> Container `/home/developer/.ssh-host` (read-only)
- Worktrees: Host `~/Projects/worktrees/<branch>` -> Container `/home/developer/workspace/<repo>` (read-write, added dynamically by `scripts/worktree-env.sh`)

## Webhooks & Callbacks

**Incoming:**
- None

**Outgoing:**
- None

---

*Integration audit: 2026-02-02*
