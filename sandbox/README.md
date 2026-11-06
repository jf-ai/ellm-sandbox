# ellm-sandbox

Sandboxed Docker environment for running Letta Code in YOLO mode.

## DISCLAIMER
No guarentees are made about the quality of the sandboxing! I am new to docker and so I am not 100% confident in the isolation! Use at your own risk!

## Quick Start

```powershell
# Build the image (first time only)
docker build -t ellm-dev .

# Launch (creates or starts container with C:\Git mounted)
.\launch.ps1

# Inside container (Opus and Sonnet pre-pinned)
letta -n Opus --yolo
# or
letta -n Sonnet --yolo

# Open additional shells into same container
docker exec -it ellm-dev bash

# Later: restart same container
docker start -ai ellm-dev
```

## How It Works

- **Agent brain** (memory, state) lives on your Letta server
- **Tool execution** (Bash, Read, Write) runs inside the container
- **C:\Git** is mounted at `/workspace/git` — full read/write access to repos
- Rest of host filesystem remains isolated (no `rm -rf jamesBabyPictures`)

See [How2Yolo.md](How2Yolo.md) for full design details.

## Dev container and test sibling (Linux, `ellm-dev-build.sh`)

`./ellm-dev-build.sh` builds the `ellm-dev` image and (re)creates the `ellm-dev` container. Flags:
`--name NAME` (default `ellm-dev`), `--port PORT` (bridge-published and passed to fs_proxy, default 8080),
`--mount SRC:DST[:ro]` (repeatable; replaces the default `$GIT_PATH` mount entirely, order kept),
`--no-build` (reuse the existing image), `--fs-proxy-src DIR` (default `$GIT_PATH/Agent-Home/src/mcp_tools`),
`--no-host-gateway` (don't map `host.docker.internal`).
Only the container named by `--name` is ever stopped or removed.

`./ellm-test-sibling.sh SLOT [extra args]` launches an isolated sibling for test slot N: container `ellm-test-N`,
port `8080+N` (`--no-build`). It sees only `$GIT_PATH/testing/fixtures/slot-N`, mounted as `$GIT_PATH`, plus
`$GIT_PATH/.uv-python` read-only. It doesn't map `host.docker.internal`. It prints the name, port and MCP URL.

**fs_proxy is baked into the image** (`/opt/fs_proxy`, own venv, label `ellm.fs_proxy_rev`). Changes to fs_proxy
now take effect on image rebuild (`./ellm-dev-build.sh`), not on container restart. This applies to `ellm-dev` too.
