FROM debian:bookworm-slim

# Build arg for mount path — must match ellm-dev-build.sh GIT_PATH
ARG GIT_PATH=/home/gossf/git

# Install system deps
RUN apt-get update && apt-get install -y \
    curl \
    git \
    build-essential \
    ca-certificates \
    nano \
    clang \
    mold \
    pkg-config \
    libssl-dev \
    poppler-utils \
    && rm -rf /var/lib/apt/lists/*

# Install Node 20 LTS
RUN curl -fsSL https://deb.nodesource.com/setup_20.x | bash - \
    && apt-get install -y nodejs

# Install Claude Code CLI (pinned) — backend for fs_proxy's MCP tool server
# (claude mcp serve). PIN THE VERSION: CC's tool surface drifts between releases;
# after any upgrade, verify tools/list still matches the fs_proxy allowlist
# (Read/Edit/Write/Bash). DISABLE_AUTOUPDATER=1 below prevents runtime drift.
RUN npm install -g @anthropic-ai/claude-code@2.1.300

# Install uv (to /usr/local/bin so non-root users can access it)
RUN curl -LsSf https://astral.sh/uv/install.sh | UV_INSTALL_DIR=/usr/local/bin sh

# Install Python 3.13 for container-local tooling (agent-commit, etc.)
# This stays in /opt — not on the shared mount — because it's container-specific.
RUN UV_PYTHON_INSTALL_DIR=/opt/uv/python uv python install 3.13

# Create shared Python venv for scripts (container-local) TODO: might not need this anymroe. Line above could potentially go too.
RUN UV_PYTHON_INSTALL_DIR=/opt/uv/python uv venv /opt/ellm --python 3.13
ENV PATH="/opt/ellm/bin:$PATH"

# Runtime UV settings: use managed Python from shared mount so venv symlinks
# resolve identically on both host and container.
ENV UV_PYTHON_INSTALL_DIR=${GIT_PATH}/.uv-python
ENV UV_MANAGED_PYTHON=1
ENV GIT_PATH=${GIT_PATH}

# Install agent-commit script for clean git identity
COPY agent-commit /opt/ellm/bin/agent-commit
RUN chmod +x /opt/ellm/bin/agent-commit

# Create non-root user matching host UID/GID
RUN groupadd -g 1000 ellm && \
    useradd -u 1000 -g 1000 -m -s /bin/bash ellm

USER ellm

# Install Rust toolchain via rustup
RUN curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y --default-toolchain 1.90.0
ENV PATH="/home/ellm/.cargo/bin:$PATH"

# Set working directory
WORKDIR /workspace

# Environment
ENV TERM="xterm-256color"
ENV EDITOR="nano"
ENV COLORTERM="truecolor"
ENV DISABLE_AUTOUPDATER="1"
ENV CLAUDE_CONFIG_DIR=${GIT_PATH}/.claude-ellm

CMD ["bash"]
