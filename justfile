# Ralph-TUI Sandbox container management

build:
    podman build -t ralph-tui-sandbox .

run project-dir:
    podman run -it --rm \
      --userns=keep-id \
      -v {{project-dir}}:/workspace:rw \
      -v ~/.ssh:/home/$USER/.ssh:ro \
      -v ~/.gnupg:/home/$USER/.gnupg:ro \
      -v ~/.config/jj:/home/$USER/.config/jj:ro \
      -v claude-data:/home/$USER/.claude \
      -v apt-cache:/var/cache/apt \
      -v bun-cache:/home/$USER/.bun \
      -v cargo-registry:/home/$USER/.cargo/registry \
      ralph-tui-sandbox

login:
    podman run -it --rm \
      --userns=keep-id \
      --network=host \
      -v claude-data:/home/$USER/.claude \
      ralph-tui-sandbox \
      claude login

shell project-dir:
    podman run -it --rm \
      --userns=keep-id \
      -v {{project-dir}}:/workspace:rw \
      -v claude-data:/home/$USER/.claude \
      ralph-tui-sandbox \
      /bin/bash

clean:
    podman rmi ralph-tui-sandbox
    podman volume rm claude-data apt-cache bun-cache cargo-registry
