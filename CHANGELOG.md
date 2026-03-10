# Changelog

All notable changes to stAirCase are documented here.

Format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/). This project uses [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.0.0] — 2026-03-09

Initial release.

### Workspace & App Management

- **`staircase init`** — scaffolds `product/`, `agent/`, `.staircase/tmp/`, and `manifest.json`.
- **`staircase register <app> [--symlink]`** — creates directory structure for a new app and records it in the manifest. `--symlink` enables context symlinks at registration time.

### Task Lifecycle

- **`staircase task new <app> <task-id>`** — creates a task directory, writes `active/context.json`, and sets the task as active in the manifest.
- **`staircase task switch <app> <task-id> [--symlink]`** — saves the current active context back to the previous task directory, loads the target task's context into `active/`, and updates the manifest. `--symlink` promotes an app to symlink mode inline.
- **`staircase task list <app>`** — lists all tasks with `*` marking the active one and last-modified timestamps.
- All context writes are atomic (`mktemp` + `mv`) — no partial states on crash.
- Context JSON is built with `jq -n` — task IDs with quotes, slashes, or special characters are always safe.

### Symlinks

- **`staircase symlink enable|disable <app>`** — creates or removes a relative symlink `product/<app>/tasks → ../../agent/<app>/active`, letting tools read context directly from the product directory.
- **`staircase symlink status`** — table showing enabled state, link health, and resolved target for every registered app.
- Symlinks auto-refresh on `task new` and `task switch` for apps with `symlinkEnabled: true`.
- Relative paths (`../../agent/<app>/active`) for cross-platform portability.

### Agent Runner

- **`staircase run <app> [--agent-config '<json>']`** — changes into `product/<app>/` and launches `ralph-tui --prd` with the active context. Agent config is merged into `context.json` before launch.
- Runs ralph-tui as a child process so `hooks.d/99-ralph-tui.sh` fires after completion.

### Workspace Inspection

- **`staircase ls`** — tree view with product paths, agent paths, task counts, active task, and symlink state. Color-coded output.
- **`staircase status [--json]`** — tabular view of all registered apps with active tasks and last-modified timestamps. `--json` outputs raw manifest.
- **`staircase explain <command> [args]`** — shows filesystem changes and manifest JSON diffs before executing. Supports `init`, `register`, `task new`, `task switch`.

### Health & Maintenance

- **`staircase doctor [--fix]`** — checks manifest validity, directory consistency, orphaned agent directories, broken symlinks, and tmp writability. `--fix` auto-repairs everything it can.
- **`staircase export <app> [--format json|tar]`** — exports agent context as JSON to stdout or as a `.tar.gz` archive.

### Git Hooks

- **`staircase hooks install <app>`** — creates `hooks.d/` stubs and installs `pre-commit` (formatter) and `post-merge` (auto-doctor) hooks into the app's Git repo. Idempotent.

### Flags & Environment

- **`--dry-run`** — every command supports dry-run mode, printing intended actions without touching disk.
- **`NO_COLOR=1`** — disables all ANSI codes for CI environments.
- **`STAIRCASE_DEBUG=1`** — enables xtrace-style command logging.

### Technical Notes

- Zero Python dependencies — pure Bash + `jq`.
- Cross-platform: macOS, Linux, WSL, Docker.
- All JSON mutations use atomic `mktemp` + `mv` writes.
- Manifest schema tracks per-app symlink preference (`symlinkEnabled`).

[1.0.0]: https://github.com/b070nd/staircase/releases/tag/v1.0.0
