# TODO

## Move fs_proxy into this repo

fs_proxy is baked into the sandbox image from `Agent-Home/src/mcp_tools`. That makes the build depend on another repo being present, and the baked version depends on which branch that repo has checked out at build time. That coupling is worse than the dependency a move would leave behind (see below).

**When:** after `Development/ClaudeCodeMCPTools` merges in Agent-Home. It's mostly fs_proxy changes, so moving the code first would collide with it.

**What moves:** `fs_proxy.py`, `cc_result_format.py` and `tests/mcp_tools/`. This repo has no Python test setup yet, so it needs one, plus a small `pyproject.toml` for fs_proxy's dependencies.

**What goes away:**
- `--fs-proxy-src` and the `--build-context fs_proxy=...` named context, replaced by a plain `COPY`
- the `FS_PROXY_REV` label logic, since fs_proxy's version becomes this repo's commit
- the hand-maintained `fastmcp` pin in the `Dockerfile` that mirrors Agent-Home's `uv.lock`

**The dependency that remains:** Agent Home's ACP bridge (`src/prototype/acp/bridge.py`) parses the Read header produced by `cc_result_format.py`. That string matching is brittle wherever the code lives. Add a test for the format, with a comment pointing to the bridge and warning against changing it.
