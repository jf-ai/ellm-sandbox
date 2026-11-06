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

# fs_proxy: baked into the image, with its own venv (container-local, like /opt/ellm).
# It needs only fastmcp (+ the claude CLI above); it does not need Agent Home's venv.
# Pin = the fastmcp version in Agent-Home/uv.lock; bump here when that changes.
# The source is copied at the end of this file, so fs_proxy changes don't rebuild later layers.
RUN UV_PYTHON_INSTALL_DIR=/opt/uv/python uv venv /opt/fs_proxy/venv --python 3.13 \
    && VIRTUAL_ENV=/opt/fs_proxy/venv uv pip install "fastmcp==3.4.7"

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

# fs_proxy source comes from a BuildKit named context (--build-context fs_proxy=<dir of mcp_tools>),
# so it is the mcp_tools package itself: fs_proxy imports `mcp_tools.cc_result_format`,
# hence it lands at /opt/fs_proxy/mcp_tools and is run as `python -m mcp_tools.fs_proxy`
# from /opt/fs_proxy. Changes to fs_proxy therefore need an image rebuild.
USER root
COPY --from=fs_proxy . /opt/fs_proxy/mcp_tools/

# Record which fs_proxy source was baked (set by ellm-dev-build.sh)
ARG FS_PROXY_REV=unknown
LABEL ellm.fs_proxy_rev=${FS_PROXY_REV}
USER ellm

CMD ["bash"]
