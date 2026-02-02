# Requirements

## v1 Requirements

### Mount Management

- [ ] **MOUNT-01**: User can mount a host directory into a running container with `cdev mount <container> <host-path> <container-path>`
- [ ] **MOUNT-02**: User can specify `--readonly` flag to mount read-only
- [ ] **MOUNT-03**: Mounts persist across container restarts (stored as LXD disk devices)
- [ ] **MOUNT-04**: User can remove a bind mount with `cdev unmount <container> <mount-name-or-path>`
- [ ] **MOUNT-05**: User can list active bind mounts on a container with `cdev mounts <container>`

### CLI Integration

- [ ] **CLI-01**: Help text for mount, unmount, and mounts commands integrated into cdev help system
- [ ] **CLI-02**: Bash tab completion updated for mount, unmount, and mounts commands

## v2 Requirements

(None identified)

## Out of Scope

- Interactive/prompt-based mount creation — not consistent with cdev UX
- Session-only (non-persistent) mounts — user wants persistence
- Batch mounting from config files — can add later if needed
- NFS or network mount types — LXD disk devices only

## Traceability

| Requirement | Phase | Status |
|-------------|-------|--------|
| MOUNT-01 | — | Pending |
| MOUNT-02 | — | Pending |
| MOUNT-03 | — | Pending |
| MOUNT-04 | — | Pending |
| MOUNT-05 | — | Pending |
| CLI-01 | — | Pending |
| CLI-02 | — | Pending |
