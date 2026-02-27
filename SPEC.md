# Ralph-TUI Sandbox: Containerized Claude Code Environment

## Overview

A containerized environment for running [ralph-tui](https://github.com/subsy/ralph-tui) (AI agent loop orchestrator) together with Claude Code inside a Podman container. The goal is to isolate Claude Code's operations from the host system so mistakes can't affect the host beyond the mounted working directory.

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

## Container Image

### Base Image

`docker.io/oven/bun:latest` (Debian-based). Required because ralph-tui depends on Bun's native features (OpenTUI).

### Container User

The image creates a non-root user to work correctly with `--userns=keep-id`. Build args control the user identity:

| Build Arg | Default | Purpose |
|---|---|---|
| `USERNAME` | `coder` | Container username |
| `USER_UID` | `1000` | User UID (should match host UID) |
| `USER_GID` | `1000` | User GID (should match host GID) |

The justfile automatically passes the host user's UID/GID via `id -u` / `id -g`. All user-space installs (Rust, bun globals) run as this user so they are accessible at runtime with `--userns=keep-id`.

### Installed Software

| Software | Install Method | Notes |
|---|---|---|
| ralph-tui | `bun install -g ralph-tui` | Entrypoint |
| claude code | `bun install -g @anthropic-ai/claude-code` | Orchestrated by ralph-tui |
| git | `apt-get install` | jj backend + claude code usage |
| jj | `cargo install jj-cli` | Pinned to v0.38.0 |
| python3 + pip | `apt-get install` | Dev toolchain |
| rustc + cargo | `rustup` minimal profile | Dev toolchain |
| emacs | `apt-get install emacs` | Full Emacs for elisp config testing |
| CLI tools | `apt-get install` | curl, wget, vim, less, ripgrep, fd-find, jq, tree, htop |
| build-essential | `apt-get install` | gcc, make, etc. |

### jj Installation

Installed via cargo since the Rust toolchain is already present:

```dockerfile
ARG JJ_VERSION=0.38.0
RUN cargo install jj-cli@${JJ_VERSION}
```

Version is pinned via `ARG` so it can be overridden at build time with `--build-arg JJ_VERSION=X.Y.Z`.

### Rust Installation

```dockerfile
RUN curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y --profile minimal
```

Minimal profile: only `rustc` and `cargo`. Additional components (clippy, rustfmt) can be added at runtime.

## Container Runtime Configuration

### User Namespace

Use `--userns=keep-id` to map the host user's UID/GID into the container. Files created in the mounted working directory will have correct ownership on the host.

### Networking

- **Normal runs**: Podman default networking (slirp4netns). Outbound HTTPS works, no inbound ports exposed.
- **Login runs**: `--network=host` for the initial `/login` OAuth flow so the browser callback can reach the container. Only used during `just login`.

### Volume Mounts

| Host Path | Container Path | Mode | Purpose |
|---|---|---|---|
| `<project-dir>` (argument) | `/workspace` | `rw` | Working directory |
| `~/.ssh` | `/home/coder/.ssh` | `ro` | SSH keys for git/jj |
| `~/.gnupg` | `/home/coder/.gnupg` | `ro` | GPG keys for signing |
| `~/.config/jj` | `/home/coder/.config/jj` | `ro` | jj configuration |

### Named Volumes

| Volume Name | Container Path | Purpose |
|---|---|---|
| `claude-data` | `/home/coder/.claude` | Auth tokens, conversation history, config |
| `apt-cache` | `/var/cache/apt` | Persist apt package cache across rebuilds |
| `bun-cache` | `/home/coder/.bun` | Persist bun global packages installed at runtime |
| `cargo-registry` | `/home/coder/.cargo/registry` | Persist downloaded crate sources |

### Security

- No podman/docker socket mounted — Claude Code cannot manipulate host containers.
- SSH/GPG keys and jj config are read-only — Claude Code cannot modify credentials.
- The container has no access to host filesystem beyond the explicitly mounted project directory.
- Container exits when ralph-tui exits — no lingering processes.

## Entrypoint

ralph-tui runs as the container entrypoint. The container's lifecycle is tied to ralph-tui:

```dockerfile
WORKDIR /workspace
ENTRYPOINT ["ralph-tui"]
```

When ralph-tui exits (normally or via error), the container stops.

## VCS Strategy

- Both `git` and `jj` are available inside the container.
- jj uses git as its backend.
- Claude Code should be instructed (via CLAUDE.md or ralph-tui config) to run `jj commit` after completing each task.
- Host jj config is mounted read-only so signing and user identity work correctly.

## Justfile

Lives in the repo root. Recipes:

### `just build`

Build the container image (passes host UID/GID as build args):

```
podman build \
  --build-arg USERNAME=coder \
  --build-arg USER_UID=$(id -u) \
  --build-arg USER_GID=$(id -g) \
  -t ralph-tui-sandbox .
```

### `just run <project-dir>`

Run the container with a project directory mounted:

```
podman run -it --rm \
  --userns=keep-id \
  -v <project-dir>:/workspace:rw \
  -v ~/.ssh:/home/coder/.ssh:ro \
  -v ~/.gnupg:/home/coder/.gnupg:ro \
  -v ~/.config/jj:/home/coder/.config/jj:ro \
  -v claude-data:/home/coder/.claude \
  -v apt-cache:/var/cache/apt \
  -v bun-cache:/home/coder/.bun \
  -v cargo-registry:/home/coder/.cargo/registry \
  ralph-tui-sandbox
```

The `coder` username in mount paths matches the `USERNAME` build arg (default: `coder`).

### `just login`

Run the container with host networking to complete Claude Code OAuth:

```
podman run -it --rm \
  --userns=keep-id \
  --network=host \
  -v claude-data:/home/coder/.claude \
  ralph-tui-sandbox \
  claude login
```

The user copies the printed OAuth URL to their host browser. Auth tokens persist in the `claude-data` volume.

### `just shell <project-dir>`

Drop into a bash shell inside the container (for debugging):

```
podman run -it --rm \
  --userns=keep-id \
  -v <project-dir>:/workspace:rw \
  -v claude-data:/home/coder/.claude \
  ralph-tui-sandbox \
  /bin/bash
```

### `just clean`

Remove the image and named volumes:

```
podman rmi ralph-tui-sandbox
podman volume rm claude-data apt-cache bun-cache cargo-registry
```

## Known Limitations & Future Considerations

1. **Image size**: Full Emacs + Rust toolchain + build-essential will make the image large (~2-3GB). Multi-stage builds could help but add complexity.
2. **jj version pinning**: Must manually update `JJ_VERSION` in the Containerfile when new versions are released. Building from source via cargo adds to image build time but avoids binary target/archive compatibility concerns.
3. **No container nesting**: Claude Code cannot run podman/docker commands. If a project requires containerized testing, this limitation will need to be revisited.
4. **OAuth flow**: The `/login` step requires a separate `just login` invocation with host networking. This is a one-time setup per volume.
5. **Portability**: Currently lives in this repo. Can be extracted to a standalone tool later.
6. **Runtime package installs**: apt/bun/cargo installs at runtime are cached in named volumes but not baked into the image. Rebuild the image to make them permanent.
7. **Emacs GUI**: Full Emacs is installed but the container has no display server. Emacs will run in terminal mode (`emacs -nw`) or batch mode (`emacs --batch`). If GUI testing is needed, X11 forwarding or Wayland socket mounting would need to be added.
