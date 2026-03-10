# PRD: stAirCase v1.0 — AI Workspace Orchestrator

## Overview

stAirCase is a Bash CLI that orchestrates **product repos** (`product/`) ↔ **AI context repos** (`agent/`) for ralph-tui and agentic workflows. It manages task context with atomic JSON state, `jq`-based manifest management, a dual hooks system (Git + hooks.d/), optional symlinks for native-feeling developer workflows, and cross-platform portability (macOS/Linux/WSL/Docker).

## Goals

- Ship a single Bash script (`staircase`) that works on macOS, Linux, WSL, and Docker
- Manage workspace state through an atomic JSON manifest at `.staircase/manifest.json`
- Require `bash` 4+ and `jq` as the sole external dependencies
- Implement all core commands with consistent UX (colored output, `--dry-run`, `--json`)
- Optional symlinks (`product/<app>/tasks → agent/<app>/active`) for direct context access from product directories
- Both Git hooks (pre-commit, post-merge) and stAirCase lifecycle hooks (`hooks.d/`)
- Export in both tar.gz and JSON formats
- Pass the full quality gate suite on every story

## Quality Gates

These commands must pass for every user story:
- `shellcheck staircase` — Bash linting (no warnings)
- `bats tests/integration.bats` — Integration test suite (122 tests)
- `./staircase doctor` — Self-healing check exits 0

---

## User Stories

### US-001: Colored output, --dry-run, and environment flags
As a developer, I want all staircase commands to support `--dry-run` and produce consistent colored output so that I can understand and audit actions before they run.

**Acceptance Criteria:**
- [x] Color helpers: `_info` (cyan →), `_ok` (green ✔), `_warn` (yellow ⚠), `_err` (red ✖) — all write to stderr
- [x] `NO_COLOR=1` disables all ANSI codes (CI-safe)
- [x] `STAIRCASE_DEBUG=1` enables xtrace-style command logging
- [x] `--dry-run` is parsed globally and respected by every command that writes state
- [x] `--dry-run` outputs a `[DRY RUN]` prefix on every action that would be taken
- [x] `--version` prints `staircase 1.0.0`
- [x] `--help` prints usage with all commands and flags

**Tests:** NO_COLOR suppresses ANSI, --version prints version, --help prints usage, unknown commands exit 1

---

### US-002: Workspace init
As a developer, I want to run `staircase init` in any directory so that the workspace scaffolding is created safely and idempotently.

**Acceptance Criteria:**
- [x] Creates `product/`, `agent/`, `.staircase/tmp/` directories
- [x] Creates `.staircase/manifest.json` with `{"version":"1.0","projects":{}}` if not present
- [x] Re-running `staircase init` is a no-op (no error, no data loss)
- [x] Outputs `✔ initialized` or `✔ already initialized`
- [x] `--dry-run` prints what would be created without touching disk
- [x] All output goes to stderr; stdout is clean

**Tests:** init on empty dir, idempotent re-init, manifest schema, first run vs second run output, stderr-only output

---

### US-003: Register a project
As a developer, I want to run `staircase register <app> [--symlink]` so that an existing product repo is wired to a new agent context directory.

**Acceptance Criteria:**
- [x] Creates `product/<app>/` and `agent/<app>/active/`, `agent/<app>/tasks/`, `agent/<app>/structure/`
- [x] Adds entry to `.staircase/manifest.json` via atomic write (`mktemp` + `mv`)
- [x] `jq` is used for all manifest reads and writes — no string-concat JSON
- [x] `--symlink` flag creates `product/<app>/tasks → ../../agent/<app>/active` and sets `symlinkEnabled: true` in manifest
- [x] Errors if `<app>` is already registered (exit 1)
- [x] Errors if run outside a workspace (exit 1)

**Tests:** register new app, duplicate (exit 1), missing name (exit 1), outside workspace (exit 1), --symlink creates link + manifest flag, without --symlink no link

---

### US-004: Create a new task
As a developer, I want to run `staircase task new <app> <task-id>` so that a task context is created and set as the active task.

**Acceptance Criteria:**
- [x] Creates `agent/<app>/tasks/<task-id>/` directory
- [x] Writes `agent/<app>/active/context.json` via `jq -n` (safe with special characters in task IDs)
- [x] `context.json` schema: `{ taskId, app, created (ISO-8601), stories: [], files: [], gitDiff: "" }`
- [x] Updates `manifest.json` `activeTask` field atomically
- [x] Refreshes symlink if enabled for the app
- [x] Errors if `<app>` is not registered (exit 1)

**Tests:** create on registered app, task dir + context created, schema validation, activeTask updated, unregistered app (exit 1), special characters in task ID, symlink refresh

---

### US-005: Switch active task
As a developer, I want to run `staircase task switch <app> <task-id> [--symlink]` so that I can atomically rotate between existing tasks.

**Acceptance Criteria:**
- [x] Saves current `active/context.json` to `tasks/<previousTaskId>/context.json`
- [x] Copies `tasks/<task-id>/context.json` → `active/context.json` atomically
- [x] Updates `manifest.json` `activeTask` to `<task-id>`
- [x] `--symlink` flag enables symlink mode one-shot (persisted in manifest)
- [x] Refreshes existing symlink if enabled
- [x] Errors if `<task-id>` directory does not exist (exit 1 + suggestion)

**Tests:** switch between tasks, manifest updated, context saved/restored with custom data, non-existent task (exit 1), --symlink one-shot, symlink refresh

---

### US-006: List tasks
As a developer, I want to run `staircase task list <app>` so that I can see all tasks for an app with the active one marked.

**Acceptance Criteria:**
- [x] Lists all task directories under `agent/<app>/tasks/`
- [x] Active task marked with `*`
- [x] Shows last-modified timestamp per task
- [x] Errors if `<app>` is not registered (exit 1)

**Tests:** all tasks shown, active marker on correct task, unregistered app (exit 1), empty tasks dir

---

### US-007: Symlink management
As a developer, I want to manage symlinks between product and agent directories so that tools can read context directly from product repos.

**Acceptance Criteria:**
- [x] `staircase symlink enable <app>` creates relative symlink `product/<app>/tasks → ../../agent/<app>/active`
- [x] `staircase symlink disable <app>` removes symlink and clears manifest flag
- [x] `staircase symlink status` shows table with enabled state, link health, and resolved target
- [x] Symlinks auto-refresh on `task new` and `task switch` for enabled apps
- [x] Idempotent — enable on already-enabled exits 0, disable on already-disabled exits 0
- [x] Fails if `product/<app>/tasks` is a real directory (not a symlink)
- [x] `doctor` detects missing/broken symlinks; `doctor --fix` repairs them

**Tests:** enable creates link, manifest flag set, idempotent, readable through symlink, real dir blocks enable, disable removes link, disable idempotent, status table, survives switch cycle, unregistered app errors, unknown subcommand errors

---

### US-008: Run ralph-tui for a project
As a developer, I want to run `staircase run <app>` so that ralph-tui launches in the correct product directory with the active context injected.

**Acceptance Criteria:**
- [x] Changes into `product/<app>/` before launching
- [x] Launches `ralph-tui --prd ../agent/<app>/active/context.json` as a child process
- [x] `--agent-config '<json>'` merges config into `context.json` before launch
- [x] Runs `hooks.d/99-ralph-tui.sh` after ralph-tui exits
- [x] Errors if product dir or context.json missing (exit 1 with hints)
- [x] `--dry-run` prints resolved command without executing

**Tests:** missing product dir (exit 1), missing context (exit 1 with hint), dry-run prints command, dry-run doesn't modify context, dry-run with --agent-config

---

### US-009: Workspace inspection (ls + status)
As a developer, I want `staircase ls` and `staircase status` to show workspace state at a glance.

**Acceptance Criteria:**
- [x] `ls` prints tree view: workspace root, app names (bold/cyan), product paths, agent paths, task count, active task (green), symlink state (on/off/broken/missing)
- [x] `ls` shows missing product paths in red without crashing
- [x] `status` prints table: APP, PRODUCT PATH, ACTIVE TASK, LAST MODIFIED
- [x] `status --json` outputs full manifest as pretty-printed JSON
- [x] Both commands exit 0 even with zero registered projects

**Tests:** ls with no workspace, empty workspace, registered apps with tree chars, active task, (none), task count, symlink state, missing product dir. status header, apps/tasks shown, (none), --json valid, --json contains project, no workspace --json

---

### US-010: Doctor command (self-healing)
As a developer or CI system, I want `staircase doctor [--fix]` to detect and repair broken workspace state.

**Acceptance Criteria:**
- [x] Check 1: manifest.json exists and is valid JSON (fix: recreate empty manifest)
- [x] Check 2: registered apps have `product/` and `agent/` paths (fix: deregister)
- [x] Check 3: apps with `activeTask` have `active/context.json` (fix: create empty)
- [x] Check 4: `.staircase/tmp/` exists and is writable (fix: create it)
- [x] Check 5: orphaned `agent/` directories not in manifest (report)
- [x] Check 6: apps with `symlinkEnabled: true` have valid symlinks (fix: recreate)
- [x] `--fix` applies all repairs; without it, only reports
- [x] Exits 0 if healthy; exits 1 if issues remain

**Tests:** healthy (exit 0), no workspace, missing tmp, invalid manifest, missing product dir, missing context.json, orphaned agent dir, missing symlink, broken symlink, multi-issue repair

---

### US-011: Export command
As a developer, I want `staircase export <app> [--format json|tar]` to back up or migrate agent context.

**Acceptance Criteria:**
- [x] Default `--format json`: writes manifest + active context + all saved tasks to stdout
- [x] `--format tar`: creates `staircase-export-<app>-<date>.tar.gz`
- [x] JSON output includes `app`, `exported_at`, `manifest`, `agent.active`, `agent.tasks`
- [x] Errors if `<app>` is not registered (exit 1)
- [x] `--dry-run` prints what would be exported without writing

**Tests:** json valid with correct app, active context included, saved tasks included, exported_at timestamp, tar creates file, tar contains agent dir, unknown app (exit 1), unknown format (exit 1), dry-run

---

### US-012: Git hooks install
As a developer, I want `staircase hooks install <app>` to wire up Git hooks and lifecycle hooks.

**Acceptance Criteria:**
- [x] Creates `hooks.d/` with stubs: `01-format.sh`, `99-ralph-tui.sh`
- [x] Installs pre-commit hook running `hooks.d/01-format.sh`
- [x] Installs post-merge hook running `staircase doctor --fix` silently
- [x] Stubs and git hooks are executable
- [x] Existing hooks preserved — stAirCase guard block appended
- [x] Idempotent — guard block appears exactly once after multiple installs
- [x] Requires `product/<app>/.git` to exist

**Tests:** creates hooks.d/ and git hooks, executable, idempotent guard, preserves existing, no git repo (exit 1), unregistered app (exit 1)

---

### US-013: Explain command
As a developer, I want `staircase explain <command> [args]` to preview what a command would do as a structured diff.

**Acceptance Criteria:**
- [x] Shows filesystem changes (created dirs, modified files)
- [x] Shows manifest JSON diff (before → after)
- [x] Shows context.json preview for task commands
- [x] Does not modify workspace state
- [x] Supports: `init`, `register`, `task new`, `task switch`
- [x] Exits 1 for unsupported commands with list of supported ones

**Tests:** explain init shows fs changes, explain register shows diff, explain task new shows context preview, explain task switch shows save/load, does not modify workspace, missing args (exit 1), unsupported command (exit 1)

---

### US-014: Repository structure and CI
As a contributor, I want the repository to have tests, CI, and a demo workspace so that the project is shippable.

**Acceptance Criteria:**
- [x] `tests/integration.bats` — 122 tests covering all commands (happy + error paths)
- [x] `.github/workflows/ci.yml` runs shellcheck and bats on push/PR
- [x] `examples/demo-workspace/README.md` — interactive walkthrough covering all features
- [x] `README.md` — developer-friendly documentation with install, quick start, full command reference
- [x] `CHANGELOG.md` — single 1.0.0 release with all features
- [x] `LICENSE` — MIT license
- [x] `--version` prints `staircase 1.0.0`

---

## Functional Requirements

- FR-1: All manifest writes MUST be atomic: write to `.staircase/tmp/<file>`, then `mv` to destination
- FR-2: `jq` is the sole external dependency; the script checks for `jq` and exits with a clear message if missing
- FR-3: Every command must be idempotent — safe to run multiple times with identical inputs
- FR-4: Context JSON is built with `jq -n` — task IDs with special characters never produce invalid JSON
- FR-5: `--dry-run` is a global flag parsed before command dispatch and respected by every write operation
- FR-6: Exit codes: 0 = success, 1 = user error (bad args, missing app, unresolvable issues)
- FR-7: The script must pass `shellcheck` with no warnings
- FR-8: Symlinks use relative paths (`../../agent/<app>/active`) for cross-platform portability
- FR-9: ralph-tui runs as a child process (not `exec`) so post-run hooks can fire

## Non-Goals

- No migration from the old `ws`/`vendor/layer/domain` layout (clean break)
- No Python dependency
- No support for multiple AI agents beyond ralph-tui in v1.0 (multi-agent dispatch is v2)
- No `staircase watch` live sync mode in v1.0
- No `staircase pr` PR automation in v1.0
- No container/Docker-native build in v1.0
- No web UI or TUI for stAirCase itself

## Technical Considerations

- Atomic write pattern: all JSON state goes through `.staircase/tmp/` → `mv`
- `jq` version: target `jq` 1.6+ (widely available)
- `bats-core` v1.x for testing
- ISO-8601 dates: `date -u +"%Y-%m-%dT%H:%M:%SZ"` (portable across macOS/Linux)
- Cross-platform `_file_mtime()` with `date -r` (macOS) and `stat -c` (Linux) fallbacks
- Shared validation helpers: `_require_ws`, `_require_jq`, `_require_app` reduce boilerplate
- `_build_context()` uses `jq -n` for safe JSON generation

## Open Questions (Resolved)

- **Symlinks vs no symlinks?** — Resolved: optional symlink mode via `--symlink` flag and `symlink enable/disable`. Pure JSON mode remains the default.
- **Export to file or stdout?** — Resolved: JSON goes to stdout (GitOps-friendly), tar goes to file.
- **License?** — Resolved: MIT.
