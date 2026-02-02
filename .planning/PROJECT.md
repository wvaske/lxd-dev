# Project: cdev Bind Mount Management

## What This Is

Adding bind mount management commands to `cdev`, the LXD development environment CLI. Users need the ability to mount host directories into running containers, list active mounts, and remove them — all persisted across container restarts.

## Core Value

Developers can dynamically share host directories with running containers without recreating or reconfiguring them manually through LXD.

## Context

`cdev` is a Bash CLI (~1468 lines) that manages LXD/Incus development containers. It already uses bind mounts internally (e.g., worktree flows mount repos into containers via LXD profiles/devices). This feature exposes mount management as first-class user commands.

The underlying mechanism is LXD device management via `lxc config device add/remove/show` — containers support hot-adding disk devices while running.

## Target Users

Developers using `cdev` to manage LXD dev containers who need to share additional host directories (config files, data, shared libraries) with running containers.

## Constraints

- Pure Bash (consistent with existing codebase)
- Uses `lxc` CLI for all LXD operations
- Mounts must persist across container restarts (stored in container config, not session-only)
- Must work on running containers

## Key Decisions

| Decision | Rationale | Outcome |
|----------|-----------|---------|
| CLI arguments (not interactive prompts) | Consistent with existing cdev UX pattern | Decided |
| Persistent mounts via LXD device config | Survives restarts, matches LXD model | Decided |
| Read-only flag support | Some mounts should be read-only for safety | Decided |
| Three subcommands (mount/unmount/mounts) | Clean separation of concerns | Decided |

## Requirements

### Validated

- ✓ Container creation and lifecycle management — existing
- ✓ Worktree-based bind mounts via profiles — existing
- ✓ CLI subcommand routing and help system — existing
- ✓ Bash tab completion — existing

### Active

- [ ] Mount a host directory into a running container with `cdev mount`
- [ ] Unmount a bind mount from a container with `cdev unmount`
- [ ] List active bind mounts on a container with `cdev mounts`
- [ ] Support `--readonly` flag for read-only mounts
- [ ] Mounts persist across container restarts
- [ ] Bash tab completion for new commands

### Out of Scope

- Interactive/prompt-based mount creation — not consistent with cdev UX
- Session-only (non-persistent) mounts — user wants persistence
- Mount configuration files or batch mounting — can add later if needed

---
*Last updated: 2026-02-02 after initialization*
