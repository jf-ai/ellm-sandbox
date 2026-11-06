#!/bin/bash
# Build/rebuild ellm-dev image and create container
# Use this after Dockerfile changes (or fs_proxy changes: fs_proxy is baked into the image)
# Run from: ~/git/ellm-sandbox/sandbox/
#
# With no flags: builds the image and (re)creates the "ellm-dev" container mounting $GIT_PATH.
# Flags let a second, isolated container be launched from the same image (see usage()).

set -e

# Mount path — same absolute path on host and in container for venv symlink compatibility
GIT_PATH="$HOME/git"

CONTAINER_NAME="ellm-dev"
IMAGE_NAME="ellm-dev"
PORT=8080
DO_BUILD=1
FS_PROXY_SRC="$GIT_PATH/Agent-Home/src/mcp_tools"
MOUNTS=()
HOST_GATEWAY=1

usage() {
    cat >&2 <<EOF
Usage: $0 [--name NAME] [--port PORT] [--mount SRC:DST[:ro]]... [--no-build] [--fs-proxy-src DIR] [--no-host-gateway]

  --name NAME            container name (default: $CONTAINER_NAME). Image is always '$IMAGE_NAME'.
  --port PORT            port published on the Docker bridge IP and used by fs_proxy (default: $PORT)
  --mount SRC:DST[:ro]   repeatable; if given at all, REPLACES the default $GIT_PATH:$GIT_PATH mount.
                         Order is preserved (matters for nested mounts).
  --no-build             skip the image build; use the existing '$IMAGE_NAME' image
  --fs-proxy-src DIR     directory to bake fs_proxy from (default: $FS_PROXY_SRC)
  --no-host-gateway      don't map host.docker.internal in the container
EOF
    exit 2
}

need_val() { [ $# -ge 2 ] && [ -n "$2" ] || { echo "ERROR: $1 needs a value" >&2; usage; }; }

while [ $# -gt 0 ]; do
    case "$1" in
        --name)          need_val "$@"; CONTAINER_NAME="$2"; shift 2 ;;
        --port)          need_val "$@"; PORT="$2"; shift 2 ;;
        --mount)         need_val "$@"; MOUNTS+=("$2"); shift 2 ;;
        --no-build)      DO_BUILD=0; shift ;;
        --fs-proxy-src)  need_val "$@"; FS_PROXY_SRC="$2"; shift 2 ;;
        --no-host-gateway) HOST_GATEWAY=0; shift ;;
        -h|--help)       usage ;;
        *)               echo "ERROR: unknown argument: $1" >&2; usage ;;
    esac
done

if ! [[ "$CONTAINER_NAME" =~ ^[a-zA-Z0-9][a-zA-Z0-9_.-]*$ ]]; then
    echo "ERROR: invalid container name: $CONTAINER_NAME" >&2; exit 2
fi
if ! [[ "$PORT" =~ ^[0-9]+$ ]] || [ "$PORT" -lt 1 ] || [ "$PORT" -gt 65535 ]; then
    echo "ERROR: invalid port: $PORT" >&2; exit 2
fi
# Explicit mounts replace the default entirely (the sibling must not see the real $GIT_PATH)
if [ ${#MOUNTS[@]} -eq 0 ]; then
    MOUNTS=("$GIT_PATH:$GIT_PATH")
fi
HOST_ARGS=()
if [ "$HOST_GATEWAY" = 1 ]; then
    HOST_ARGS=(--add-host host.docker.internal:host-gateway)
fi
MOUNT_ARGS=()
for m in "${MOUNTS[@]}"; do
    MOUNT_ARGS+=(-v "$m")
done

# Determine Docker bridge gateway IP so fs_proxy is only reachable via the bridge
# (accessible to containers using host.docker.internal, not exposed to LAN).
# Abort if the IP cannot be determined — an empty value would cause Docker to
# fall back to 0.0.0.0, exposing fs_proxy to the LAN.
BRIDGE_IP=$(docker network inspect bridge --format='{{range .IPAM.Config}}{{.Gateway}}{{end}}')
if [ -z "$BRIDGE_IP" ] || [ "$BRIDGE_IP" = "0.0.0.0" ]; then
    echo -e "\033[31mERROR: Could not determine Docker bridge IP. Aborting to prevent LAN exposure of fs_proxy.\033[0m"
    exit 1
fi
echo -e "\033[36mDocker bridge IP: $BRIDGE_IP\033[0m"

# Check inputs before touching any container
if [ "$DO_BUILD" = 1 ]; then
    for f in __init__.py fs_proxy.py cc_result_format.py; do
        if [ ! -f "$FS_PROXY_SRC/$f" ]; then
            echo -e "\033[31mERROR: $FS_PROXY_SRC/$f not found (--fs-proxy-src must be the mcp_tools directory)\033[0m"
            exit 1
        fi
    done
else
    if ! docker image inspect "$IMAGE_NAME" >/dev/null 2>&1; then
        echo -e "\033[31mERROR: --no-build given but image '$IMAGE_NAME' does not exist. Build it first (run without --no-build).\033[0m"
        exit 1
    fi
fi

# Stop and remove existing container of THIS name only (never any other container).
# 'docker container inspect' matches the exact name.
if docker container inspect "$CONTAINER_NAME" >/dev/null 2>&1; then
    echo -e "\033[33mRemoving existing container $CONTAINER_NAME...\033[0m"
    docker stop "$CONTAINER_NAME" 2>/dev/null || true
    docker rm "$CONTAINER_NAME"
fi

if [ "$DO_BUILD" = 1 ]; then
    # Record which fs_proxy source gets baked: repo HEAD of --fs-proxy-src, "-dirty" if
    # there are uncommitted changes under it (those get baked too).
    FS_PROXY_REV=$(git -C "$FS_PROXY_SRC" rev-parse --short HEAD 2>/dev/null || echo unknown)
    if [ "$FS_PROXY_REV" != unknown ] && [ -n "$(git -C "$FS_PROXY_SRC" status --porcelain -- . 2>/dev/null)" ]; then
        FS_PROXY_REV="$FS_PROXY_REV-dirty"
    fi
    # Build image (pass GIT_PATH so Dockerfile can set UV_PYTHON_INSTALL_DIR).
    # Named build context (COPY --from=fs_proxy) needs BuildKit, so force it on.
    echo -e "\033[36mBuilding image (fs_proxy from $FS_PROXY_SRC @ $FS_PROXY_REV)...\033[0m"
    DOCKER_BUILDKIT=1 docker build -t "$IMAGE_NAME" \
        --build-arg "GIT_PATH=$GIT_PATH" \
        --build-arg "FS_PROXY_REV=$FS_PROXY_REV" \
        --build-context "fs_proxy=$FS_PROXY_SRC" .
else
    echo -e "\033[36mSkipping build (--no-build); using existing image $IMAGE_NAME\033[0m"
fi

# fs_proxy runs from the baked copy in /opt/fs_proxy. Its claude subprocess cwd comes from
# GIT_PATH, an image ENV (same in every container made from this image).
FS_PROXY_ARGS="--host 0.0.0.0 --allowed-host host.docker.internal --pass-env UV_PYTHON_INSTALL_DIR,UV_MANAGED_PYTHON"
if [ "$PORT" != 8080 ]; then
    FS_PROXY_ARGS="$FS_PROXY_ARGS --port $PORT"
fi

# Create and start container
# CRITICAL: --add-host flag required on Linux (Windows Docker Desktop injects this automatically)
# fs_proxy is published only on the Docker bridge IP — reachable by Agent Home via
# host.docker.internal but not from the LAN. The sandbox has no access to Agent Home's
# port (bound to 127.0.0.1 only), enforcing the invariant that agents cannot reach the server API.
# The container-side port equals the host port, so --port and -p stay in sync.
echo -e "\033[36mCreating container $CONTAINER_NAME with mounts: ${MOUNTS[*]}\033[0m"
docker run -d \
    --name "$CONTAINER_NAME" \
    "${HOST_ARGS[@]}" \
    -p "${BRIDGE_IP}:${PORT}:${PORT}" \
    "${MOUNT_ARGS[@]}" \
    "$IMAGE_NAME" \
    bash -c "cd /opt/fs_proxy && exec /opt/fs_proxy/venv/bin/python -m mcp_tools.fs_proxy $FS_PROXY_ARGS"

echo -e "\033[32mContainer started! To get a shell:\033[0m"
echo -e "\033[32m  docker exec -it $CONTAINER_NAME bash\033[0m"
