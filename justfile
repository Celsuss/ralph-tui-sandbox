# Ralph-TUI Sandbox container management

container_user := "coder"
uid := `id -u`
gid := `id -g`

build:
    podman build \
      --build-arg USERNAME={{container_user}} \
      --build-arg USER_UID={{uid}} \
      --build-arg USER_GID={{gid}} \
      -t ralph-tui-sandbox .

run project-dir:
    podman run -it --rm \
      --userns=keep-id \
      -v {{project-dir}}:/workspace:rw \
      -v ~/.ssh:/home/{{container_user}}/.ssh:ro \
      -v ~/.gnupg:/home/{{container_user}}/.gnupg:ro \
      -v ~/.config/jj:/home/{{container_user}}/.config/jj:ro \
      -v claude-data:/home/{{container_user}}/.claude \
      -v apt-cache:/var/cache/apt \
      -v bun-cache:/home/{{container_user}}/.bun \
      -v cargo-registry:/home/{{container_user}}/.cargo/registry \
      ralph-tui-sandbox

login:
    podman run -it --rm \
      --userns=keep-id \
      --network=host \
      -v claude-data:/home/{{container_user}}/.claude \
      ralph-tui-sandbox \
      claude login

shell project-dir:
    podman run -it --rm \
      --userns=keep-id \
      -v {{project-dir}}:/workspace:rw \
      -v claude-data:/home/{{container_user}}/.claude \
      ralph-tui-sandbox \
      /bin/bash

clean:
    podman rmi ralph-tui-sandbox
    podman volume rm claude-data apt-cache bun-cache cargo-registry
