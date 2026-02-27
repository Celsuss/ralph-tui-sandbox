FROM oven/bun:latest

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

RUN curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y --profile minimal
ENV PATH="/root/.cargo/bin:${PATH}"

ARG JJ_VERSION=0.38.0
RUN cargo install jj-cli@${JJ_VERSION}

RUN bun install -g ralph-tui
RUN bun install -g @anthropic-ai/claude-code

WORKDIR /workspace
ENTRYPOINT ["ralph-tui"]
