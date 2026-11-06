#!/bin/bash
# Launch an isolated sibling container for test slot N: sees only its fixture (mounted AS $GIT_PATH).
# Usage: ellm-test-sibling.sh SLOT [extra ellm-dev-build.sh args]
# Slot N gets container ellm-test-N, port 8080+N and fixture $GIT_PATH/testing/fixtures/slot-N.
# No host.docker.internal: the sibling has no reason to reach the host, and that name passes
# the Host check on the main fs_proxy (:8080) if it can be resolved.
# WARNING: This is not perfect isolation from the primary sandbox, it can still be reached by hitting the
# docker internal network IP directly, and with the right port and a forged host header, fs_proxy in the main server
# will accept requests from this container
set -e
GIT_PATH="$HOME/git"
SLOT="$1"; shift || true
[[ "$SLOT" =~ ^[1-9][0-9]*$ ]] || { echo "Usage: $0 SLOT [extra args]  (SLOT must be a positive integer, got: '$SLOT')" >&2; exit 1; }
NAME="ellm-test-$SLOT"
PORT=$((8080 + SLOT))
FIXTURE="$GIT_PATH/testing/fixtures/slot-$SLOT"
mkdir -p "$FIXTURE"
echo "Slot $SLOT: container $NAME, port $PORT, fixture $FIXTURE"
echo "MCP URL for agents: http://host.docker.internal:$PORT/mcp"
exec "$(dirname "$(realpath "$0")")/ellm-dev-build.sh" --name "$NAME" --port "$PORT" --no-build --no-host-gateway \
    --mount "$FIXTURE:$GIT_PATH" --mount "$GIT_PATH/.uv-python:$GIT_PATH/.uv-python:ro" "$@"
