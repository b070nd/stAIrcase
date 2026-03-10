# stAirCase Demo Workspace

Interactive walkthrough of the full stAirCase workflow. Run every command yourself — the workspace is self-contained and disposable.

**Time:** ~5 min · **Requirements:** `bash` 4+, `jq`, `git`

## Setup

```sh
# From the repo root
export PATH="$(pwd):$PATH"
cd examples/demo-workspace
```

## 1 — Initialize

```sh
staircase init
# ✔  initialized
```

Three directories appear: `product/`, `agent/`, `.staircase/`. The manifest starts empty:

```sh
cat .staircase/manifest.json
# {"version":"1.0","projects":{}}
```

Running `init` again is safe — it's idempotent.

## 2 — Register apps

```sh
staircase register frontend
# ✔  registered 'frontend'

staircase register api --symlink
# ✔  registered 'api'
# ✔  symlink: product/api/tasks → agent/api/active
```

`frontend` uses the standard layout. `api` gets a symlink so you can access context directly from the product directory. Check what happened:

```sh
staircase ls
# /path/to/demo-workspace
# ├── api
# │   ├── product: product/api
# │   ├── agent:   agent/api
# │   ├── tasks:   0
# │   ├── active:  (none)
# │   └── symlink: on
# └── frontend
#     ├── product: product/frontend
#     ├── agent:   agent/frontend
#     ├── tasks:   0
#     ├── active:  (none)
#     └── symlink: off
```

## 3 — Preview before you act

Before creating a task, see exactly what will happen:

```sh
staircase explain task new frontend US-001
# ── explain: staircase task new frontend US-001
#
# Filesystem changes:
#   + agent/frontend/tasks/US-001/
#   ~ agent/frontend/active/context.json
#
# context.json:
# {
#   "taskId": "US-001",
#   "app": "frontend",
#   "created": "2026-03-15T...",
#   "stories": [],
#   "files": [],
#   "gitDiff": ""
# }
#
# Manifest diff:
# <       "activeTask": ...
# >       "activeTask": "US-001"
```

`explain` reads the current state and shows the diff without writing anything. Works for `init`, `register`, `task new`, and `task switch`.

## 4 — Create and switch tasks

```sh
# Create three tasks for frontend
staircase task new frontend US-001
staircase task new frontend US-002
staircase task new frontend BUG-017

# See them all
staircase task list frontend
#   US-001                2026-03-15 10:01:23
#   US-002                2026-03-15 10:01:24
# * BUG-017               2026-03-15 10:01:25
```

The `*` marks the active task. Now switch back:

```sh
staircase task switch frontend US-001
# ✔  switched to task 'US-001' for 'frontend'

# Verify — context.json now has US-001
cat agent/frontend/active/context.json | jq '.taskId'
# "US-001"

# BUG-017's context was saved automatically
cat agent/frontend/tasks/BUG-017/context.json | jq '.taskId'
# "BUG-017"
```

The switch is atomic: save old context → load new context → update manifest. Each step uses `mktemp` + `mv`, so a crash mid-switch never leaves corrupted state.

## 5 — Symlinks in action

The `api` app was registered with `--symlink`. Create a task and access it from the product directory:

```sh
staircase task new api SYNC-001

# Access context through the symlink — no need to know the agent/ path
cat product/api/tasks/context.json | jq '.taskId'
# "SYNC-001"

# The symlink is a relative path
ls -la product/api/tasks
# tasks -> ../../agent/api/active
```

Switch tasks — the symlink doesn't change, but the content behind it does:

```sh
staircase task new api SYNC-002
cat product/api/tasks/context.json | jq '.taskId'
# "SYNC-002"

staircase task switch api SYNC-001
cat product/api/tasks/context.json | jq '.taskId'
# "SYNC-001"
```

Enable symlinks on an existing app:

```sh
staircase symlink enable frontend
# ✔  symlink enabled: product/frontend/tasks → agent/frontend/active

# Check all symlink states at once
staircase symlink status
# APP                   ENABLED     LINK OK     TARGET
# --------------------  ----------  ----------  --------------------
# api                   yes         ok          ../../agent/api/active
# frontend              yes         ok          ../../agent/frontend/active
```

Disable when you're done:

```sh
staircase symlink disable frontend
# ✔  symlink disabled for 'frontend'
```

## 6 — Workspace inspection

```sh
# Tree view — quick visual check
staircase ls

# Table view — good for scripts
staircase status
# APP                   PRODUCT PATH          ACTIVE TASK           LAST MODIFIED
# --------------------  --------------------  --------------------  -------------------
# api                   product/api           SYNC-001              2026-03-15 10:02:15
# frontend              product/frontend      US-001                2026-03-15 10:01:23

# Machine-readable — pipe to jq, feed to CI
staircase status --json | jq '.projects | keys'
# ["api", "frontend"]
```

## 7 — Doctor and self-healing

```sh
staircase doctor
# ✔  workspace is healthy
```

Break something on purpose to see the repair:

```sh
# Corrupt the symlink
rm product/api/tasks

staircase doctor
# ⚠  app 'api': symlinkEnabled but product/api/tasks is not a symlink
# ✖  1 issue(s) remaining

# Auto-repair
staircase doctor --fix
# ⚠  app 'api': symlinkEnabled but product/api/tasks is not a symlink
# ✔  repaired: recreated symlink for 'api'
# ✔  all issues repaired

staircase doctor
# ✔  workspace is healthy
```

Doctor checks for: invalid manifest JSON, missing `product/` or `agent/` directories, active tasks without context files, orphaned agent directories, broken symlinks, and unwritable tmp directory.

## 8 — Export

```sh
# JSON to stdout — includes manifest, active context, and all saved tasks
staircase export api | jq '.agent.tasks | keys'
# ["SYNC-001", "SYNC-002"]

# Tar archive — good for backups or sharing
staircase export api --format tar
# ✔  exported 'api' to staircase-export-api-2026-03-15.tar.gz
```

## 9 — Git hooks

```sh
git -C product/frontend init -q
staircase hooks install frontend
# ✔  created hooks.d/01-format.sh
# ✔  created hooks.d/99-ralph-tui.sh
# ✔  installed pre-commit hook for 'frontend'
# ✔  installed post-merge hook for 'frontend'
```

Two hooks are installed:

- **pre-commit** runs `hooks.d/01-format.sh` — edit this to call `prettier`, `gofmt`, `black`, etc.
- **post-merge** runs `staircase doctor --fix` silently to keep the workspace healthy after pulls.

Running `hooks install` again is safe — it detects existing blocks and skips them.

## 10 — Dry-run mode

Every command supports `--dry-run`. Nothing touches disk:

```sh
staircase --dry-run register new-service
# →  [DRY RUN] mkdir -p product/new-service/ agent/new-service/active/ ...
# →  [DRY RUN] update .staircase/manifest.json: add project 'new-service'

staircase --dry-run task switch frontend BUG-017
# →  [DRY RUN] cp agent/frontend/active/context.json agent/frontend/tasks/US-001/context.json
# →  [DRY RUN] cp agent/frontend/tasks/BUG-017/context.json agent/frontend/active/context.json
# →  [DRY RUN] update .staircase/manifest.json: set activeTask to 'BUG-017'

staircase --dry-run symlink enable frontend
# →  [DRY RUN] ln -s ../../agent/frontend/active product/frontend/tasks
# →  [DRY RUN] update manifest: symlinkEnabled = true
```

## 11 — Run an agent

```sh
# This launches ralph-tui — skip if you don't have it installed
staircase run frontend

# With agent config injection
staircase run frontend --agent-config '{"model":"claude-sonnet","maxTokens":4096}'
```

`run` merges the agent config into `context.json`, then launches `ralph-tui --prd` from inside `product/frontend/`. After ralph-tui exits, `hooks.d/99-ralph-tui.sh` fires.

## Cleanup

```sh
# Tear down everything — it's just files
cd ../..
rm -rf examples/demo-workspace/.staircase examples/demo-workspace/product examples/demo-workspace/agent examples/demo-workspace/hooks.d
```

Or just delete the whole `demo-workspace` directory and start fresh.

## What to try next

- Register multiple apps and switch between tasks across them
- Run `staircase explain register another-app` to see manifest diffs
- Break the manifest (`echo "bad" > .staircase/manifest.json`) and watch `doctor --fix` recover
- Set `NO_COLOR=1` and pipe output to see CI-safe formatting
- Set `STAIRCASE_DEBUG=1` to trace every command
