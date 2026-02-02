# Roadmap: cdev Bind Mount Management

## Overview

Adding bind mount management to cdev through three new commands (mount, unmount, mounts) that allow developers to dynamically share host directories with running LXD containers. All mounts persist across container restarts using LXD disk devices.

**Depth:** Quick (2 phases)
**Coverage:** 7/7 v1 requirements mapped

---

## Phase 1: Core Mount Operations

**Goal:** Users can mount, unmount, and list bind mounts on running containers with persistence.

**Dependencies:** None (builds on existing cdev LXD integration)

**Requirements:**
- MOUNT-01: Mount host directory into running container
- MOUNT-02: Support --readonly flag for read-only mounts
- MOUNT-03: Mounts persist across container restarts
- MOUNT-04: Unmount bind mounts by name or path
- MOUNT-05: List active bind mounts on container

**Success Criteria:**
1. User can run `cdev mount mycontainer ~/data /mnt/data` and access host files from inside container
2. User can add `--readonly` flag and container cannot modify mounted files
3. User can restart container and mounted directories remain accessible
4. User can run `cdev unmount mycontainer /mnt/data` to remove a mount
5. User can run `cdev mounts mycontainer` and see all active bind mounts with paths

**Plans:** 1 plan

Plans:
- [ ] 01-01-PLAN.md — Implement mount/unmount/mounts commands with LXD device operations

---

## Phase 2: CLI Integration

**Goal:** Mount commands integrate seamlessly with cdev's help and completion systems.

**Dependencies:** Phase 1 (commands must exist before documenting)

**Requirements:**
- CLI-01: Help text for mount, unmount, and mounts commands
- CLI-02: Bash tab completion for mount, unmount, and mounts commands

**Success Criteria:**
1. User can run `cdev help mount`, `cdev help unmount`, `cdev help mounts` and see usage documentation
2. User can run `cdev mount` with no args and receive helpful error with usage info
3. User can type `cdev moun<TAB>` and bash completes to `cdev mount`
4. User can type `cdev mount <TAB>` and bash suggests available container names

**Plans:** 0 plans

Plans:
- [ ] TBD (created by /gsd:plan-phase 2)

---

## Progress Tracking

| Phase | Goal | Requirements | Status | Progress |
|-------|------|--------------|--------|----------|
| 1 - Core Mount Operations | Mount management commands with persistence | 5 | Pending | 0% |
| 2 - CLI Integration | Help and completion | 2 | Pending | 0% |

**Overall Progress:** 0/7 requirements complete (0%)

---

*Last updated: 2026-02-02*
