# ralph-tui-sandbox

Sandboxed [Claude Code](https://github.com/anthropics/claude-code) environment, orchestrated by [ralph-tui](https://github.com/subsy/ralph-tui), running inside a rootless Podman container.

## Overview

This project packages ralph-tui and Claude Code into an isolated Podman container so that Claude Code's file system access is limited to a single mounted project directory. The host's SSH keys, GPG keys, and jj config are mounted read-only, and auth tokens persist across runs via a named volume. A `justfile` provides all the build/run/login recipes.

## Architecture

```
Host (Arch Linux)
├── Podman (rootless)
│   └── Container (Debian-based, bun image)
│       ├── ralph-tui (entrypoint)
│       ├── claude code (orchestrated by ralph-tui)
│       ├── git, jj (VCS)
│       ├── python3, rustc+cargo (minimal), emacs
│       └── common CLI tools
├── Mounted volumes
│   ├── /workspace (project dir, read-write)
│   ├── ~/.ssh (read-only)
│   ├── ~/.gnupg (read-only)
│   ├── ~/.config/jj (read-only)
│   └── claude-data (named volume for ~/.claude)
└── Justfile (build/run/login recipes)
```

## Prerequisites

- [Podman](https://podman.io/) (rootless mode)
- [just](https://github.com/casey/just) command runner
- Optionally on the host: `~/.ssh`, `~/.gnupg`, `~/.config/jj` (mounted read-only into the container)

## Quick Start

```bash
# 1. Build the container image
just build

# 2. Authenticate Claude Code (one-time setup)
just login

# 3. Run ralph-tui on a project
just run /path/to/your/project
```

## Recipes

| Recipe | Usage | Description |
|---|---|---|
| `build` | `just build` | Build the container image (passes host UID/GID automatically) |
| `run` | `just run <project-dir>` | Launch ralph-tui with a project directory mounted at `/workspace` |
| `login` | `just login` | Run Claude Code OAuth login (uses host networking for browser callback) |
| `shell` | `just shell <project-dir>` | Drop into a bash shell inside the container for debugging |
| `test` | `just test` | Run the automated test suite to verify the container |
| `clean` | `just clean` | Remove the image and all named volumes |

## What's Inside

| Software | Notes |
|---|---|
| ralph-tui | Container entrypoint |
| Claude Code | Orchestrated by ralph-tui |
| git, jj (v0.38.0) | Version control (jj uses git backend) |
| python3, pip | Dev toolchain |
| rustc, cargo | Minimal Rust toolchain via rustup |
| emacs | Full Emacs (terminal/batch mode) |
| build-essential | gcc, make, etc. |
| CLI tools | curl, wget, vim, less, ripgrep, fd-find, jq, tree, htop |

## Security

- No podman/docker socket mounted — Claude Code cannot manipulate host containers.
- SSH/GPG keys and jj config are read-only — credentials cannot be modified.
- No host filesystem access beyond the explicitly mounted project directory.
- `--userns=keep-id` maps host UID/GID so files have correct ownership.
- Container exits when ralph-tui exits — no lingering processes.

## Testing

Run the automated test suite:

```bash
just test
```

The suite verifies: image build, user identity, all installed tools, working directory setup, read-only mount enforcement, named volume persistence, outbound network access, entrypoint configuration, and container isolation. See [SPEC.md — Testing](SPEC.md#testing) for full details.

## License

MIT
