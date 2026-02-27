FROM docker.io/oven/bun:latest

ARG USERNAME=coder
ARG USER_UID=1000
ARG USER_GID=1000

RUN apt-get update && apt-get install -y \
    git \
    python3 \
    python3-pip \
    emacs \
    build-essential \
    curl \
    wget \
    vim \
    less \
    ripgrep \
    fd-find \
    jq \
    tree \
    htop \
    ca-certificates \
    && rm -rf /var/lib/apt/lists/*

# Install bun globals to a shared location accessible by all users
ENV BUN_INSTALL="/usr/local"
RUN bun install -g ralph-tui
RUN bun install -g @anthropic-ai/claude-code

# Create non-root user (handle UID conflict with base image's bun user)
RUN if id -u ${USER_UID} >/dev/null 2>&1; then \
      existing=$(getent passwd ${USER_UID} | cut -d: -f1); \
      usermod -l ${USERNAME} -d /home/${USERNAME} -m "$existing"; \
      groupmod -n ${USERNAME} $(getent group ${USER_GID} | cut -d: -f1) 2>/dev/null || true; \
    else \
      groupadd --gid ${USER_GID} ${USERNAME} 2>/dev/null || true; \
      useradd --uid ${USER_UID} --gid ${USER_GID} -m ${USERNAME}; \
    fi

USER ${USERNAME}

# Install Rust and cargo tools as the non-root user
RUN curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y --profile minimal
ENV PATH="/home/${USERNAME}/.cargo/bin:${PATH}"

ARG JJ_VERSION=0.38.0
RUN cargo install jj-cli@${JJ_VERSION}

WORKDIR /workspace
ENTRYPOINT ["ralph-tui"]
