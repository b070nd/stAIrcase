# stAirCase

**AI workspace orchestrator** — structure your repos, manage agent context, switch between cases atomically.

stAirCase gives your AI coding agents a workspace where projects are organized under vendors, broken into components, and every unit of work gets its own *case* — a saved context that can be switched instantly. Think of it like Composer for AI agent workflows.

```
my-workspace/
├── .staircase/                ← workspace config + manifest
├── acme/                      ← vendor
│   ├── webshop/               ← project
│   │   ├── .staircase/        ← agent context (cases, active state)
│   │   ├── storefront/        ← component
│   │   ├── checkout-api/      ← component
│   │   └── admin-panel/       ← component
│   └── cms/
│       ├── .staircase/
│       ├── frontend/
│       └── backend/
└── hooks.d/                   ← lifecycle hooks
```

## Install

```bash
# macOS (Homebrew)
brew tap b070nd/staircase
brew install staircase

# Any platform
curl -sL https://raw.githubusercontent.com/b070nd/stAIrcase/main/staircase \
  -o /usr/local/bin/staircase && chmod +x /usr/local/bin/staircase
```

**Requirements:** `bash` 4+, `jq`

## Quick Start

```bash
mkdir my-workspace && cd my-workspace

staircase init                                          # create workspace
staircase project add acme/webshop                      # add a project (auto-creates vendor)
staircase component add acme/webshop storefront api     # add components
staircase case new acme/webshop SPRINT-1                # open a case
staircase run acme/webshop                              # launch your agent
```

That's it. Your agent gets a context file listing the project, its components, and the active case.

## Concepts

**Vendor** — a namespace grouping (`acme`, `client-x`). Just a directory.

**Project** — a product or service (`acme/webshop`). Has its own `.staircase/` with agent context. This is the unit of work.

**Component** — a subproject within a project (`storefront`, `checkout-api`). The agent sees all components when running against a project.

**Case** — a unit of work scoped to a project. Each case gets its own context snapshot. Switch between cases atomically — the previous context is saved, the new one is loaded.

## Commands

### Workspace

```bash
staircase init [--name <n>]             # Create workspace in current directory
staircase config runner claude-code     # Set default agent runner
staircase config --list                 # Show resolved config with sources
```

`init` creates `.staircase/config.json`, `.staircase/manifest.json`, `.staircase/tmp/`, and `hooks.d/`.

### Structure

```bash
staircase vendor add acme                                   # create vendor
staircase vendor list                                       # list vendors
staircase vendor remove acme                                # remove (must be empty)

staircase project add acme/webshop                          # create project
staircase project list                                      # list all projects
staircase project list acme                                 # filter by vendor
staircase project info acme/webshop                         # show details
staircase project remove acme/webshop                       # remove from manifest

staircase component add acme/webshop storefront api admin   # add components (multi)
staircase component list acme/webshop                       # list components
staircase component remove acme/webshop admin               # remove one
```

`project add` auto-creates the vendor if it doesn't exist yet.

### Cases

```bash
staircase case new acme/webshop SPRINT-1        # open a new case, set as active
staircase case new acme/webshop SPRINT-2        # open another
staircase case switch acme/webshop SPRINT-1     # switch back — context restored
staircase case list acme/webshop                # list all cases (* = active)
staircase case info acme/webshop                # show active context
staircase case info acme/webshop SPRINT-2       # show specific case
```

When you switch cases, staircase saves the current `active/context.json` back to the previous case's directory before loading the new one. Both writes use atomic `mktemp` + `mv`.

### Running Your Agent

```bash
staircase run acme/webshop                              # launch with default runner
staircase run acme/webshop --runner claude-code          # override runner
staircase run acme/webshop --config '{"model":"gpt4"}'  # inject agent config
```

`run` resolves the runner through the config cascade, changes into the project directory, and launches:

```
<runner> --prd .staircase/active/context.json
```

The context file includes the full component list, so the agent knows its scope.

**Runner resolution order** (highest wins): `--runner` flag → `STAIRCASE_RUNNER` env → project config → workspace config → `ralph-tui`

### Inspection

```bash
staircase ls              # tree view
staircase status          # table view
staircase status --json   # machine-readable manifest
```

**`ls` output:**
```
my-workspace  (/home/user/my-workspace)
├── acme
│   ├── cms
│   │   ├── case:       BUG-042
│   │   └── components: 2
│   └── webshop
│       ├── case:       SPRINT-1
│       └── components: 3
└── clientx
    └── landing
        ├── case:       (none)
        └── components: 1
```

**`status` output:**
```
VENDOR        PROJECT               ACTIVE CASE       COMPS   MODIFIED
------------  --------------------  ----------------  ------  -------------------
acme          cms                   BUG-042           2       2025-07-01 10:05:12
acme          webshop               SPRINT-1          3       2025-07-01 10:01:23
clientx       landing               (none)            1       -
```

### Health Checks

```bash
staircase doctor          # check workspace health
staircase doctor --fix    # auto-repair issues
```

Doctor checks for: missing/invalid config and manifest, missing vendor/project/component directories, missing context files for active cases, and unwritable tmp directory. `--fix` repairs everything it can.

### Export

```bash
staircase export acme/webshop               # JSON to stdout
staircase export acme/webshop --format tar  # .tar.gz archive
```

JSON export includes manifest entry, active context, and all saved case contexts.

### Git Hooks

```bash
staircase hooks install acme/webshop
```

Scans the project root and all component directories for `.git` repos and installs:

- **pre-commit** — runs `hooks.d/01-format.sh` (stub for your formatter)
- **post-merge** — runs `staircase doctor --fix` silently

Edit `hooks.d/01-format.sh` to wire up `prettier`, `gofmt`, `black`, etc.

### Dry Run

Every command supports `--dry-run`:

```bash
staircase --dry-run project add acme/new-service
staircase --dry-run case new acme/webshop SPRINT-99
staircase --dry-run component add acme/webshop payments
```

Prints what would happen without touching disk.

## Context File

Each case produces a `context.json` in the project's `.staircase/active/`:

```json
{
  "caseId": "SPRINT-1",
  "vendor": "acme",
  "project": "webshop",
  "components": ["storefront", "checkout-api", "admin-panel"],
  "created": "2025-07-01T10:00:00Z",
  "stories": [],
  "files": [],
  "gitDiff": ""
}
```

The agent reads this as its PRD source. The schema is intentionally minimal — extend `stories`, `files`, and `gitDiff` as your workflow needs.

## Configuration

**Workspace config** (`.staircase/config.json`):
```json
{
  "version": "1.0",
  "name": "my-workspace",
  "runner": "ralph-tui",
  "hooks_dir": "hooks.d"
}
```

**Project config** (`acme/webshop/.staircase/config.json`):
```json
{
  "vendor": "acme",
  "project": "webshop",
  "components": ["storefront", "checkout-api", "admin-panel"],
  "runner": null
}
```

Setting `runner` in a project config overrides the workspace default for that project. `null` means inherit.

**`config --list`** shows resolved values with sources:

```
KEY               VALUE                 SOURCE
----------------  --------------------  --------
runner            ralph-tui             config
hooks_dir         hooks.d               config
tmp_dir           .staircase/tmp        default
name              my-workspace          config
```

## Environment Variables

All env vars override config values. Resolution order (highest wins): CLI flags → env vars → project config → workspace config → defaults.

| Variable | Default | Description |
|----------|---------|-------------|
| `STAIRCASE_DIR` | Auto-detect upward | Workspace root override |
| `STAIRCASE_TMP_DIR` | `.staircase/tmp/` | Temp dir for atomic writes |
| `STAIRCASE_HOOKS_DIR` | `hooks.d/` | Hooks directory |
| `STAIRCASE_RUNNER` | `ralph-tui` | Agent runner command |
| `STAIRCASE_DEBUG` | *(unset)* | Enable debug logging |
| `NO_COLOR` | *(unset)* | Disable colored output |
| `DRY_RUN` | *(unset)* | Same as `--dry-run` flag |

```bash
# Use a different runner for this session
STAIRCASE_RUNNER=claude-code staircase run acme/webshop

# Point to a workspace elsewhere
STAIRCASE_DIR=/opt/workspaces/client staircase ls
```

## Design Decisions

**Why vendor / project / component?**
Real work is multi-tenant and multi-layered. A webshop has a storefront, an API, and an admin panel. They live under one project because the agent needs to see all of them when working a case. Vendors keep client work separated.

**Why "cases"?**
A case is a unit of work — a sprint, a bug, a feature. Switching cases atomically saves the current context and loads the new one. No stale state, no manual file juggling. And it makes the tool name work: stair*case* manages *cases*.

**Why agent context inside the project?**
The `.staircase/` directory lives inside each project (`acme/webshop/.staircase/`), not in a separate tree. This means the context travels with the project and the agent can reference it with a simple relative path.

**Why atomic writes?**
Every JSON mutation goes through `mktemp` + `mv`. If your machine crashes mid-write, you get either the old file or the new file — never a corrupted half-write.

**Why `jq`?**
The alternative is parsing JSON in pure bash with `sed`, which breaks the moment someone uses a quote in a case ID. `jq` handles edge cases correctly and is available in every package manager.

**Why config cascade?**
Different projects may need different runners. The workspace sets a default, projects override it, env vars override everything. Same pattern as Composer, npm, and git config.

## License

[MIT](LICENSE) © Botond Biro
