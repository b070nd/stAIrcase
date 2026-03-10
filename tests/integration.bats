#!/usr/bin/env bats
# tests/integration.bats — staircase 1.0.0 integration tests
#
# Run:    bats tests/integration.bats
# Quiet:  bats --tap tests/integration.bats
# Filter: bats tests/integration.bats --filter "symlink"

STAIRCASE="${BATS_TEST_DIRNAME}/../staircase"

setup() {
  WORK_DIR="$(mktemp -d)"
  cd "$WORK_DIR" || return 1
  export NO_COLOR=1
}

teardown() {
  rm -rf "$WORK_DIR"
}

# ── Helper: shorthand for running staircase with stderr merged ────────────────
sc() { bash -c "'$STAIRCASE' $* 2>&1"; }

# ── Helper: init + register + task in one shot ────────────────────────────────
scaffold() {
  local app="${1:-myapp}" task="${2:-T-001}"
  sc init > /dev/null
  sc "register $app" > /dev/null
  sc "task new $app $task" > /dev/null
}

# ═══════════════════════════════════════════════════════════════════════════════
#  INIT
# ═══════════════════════════════════════════════════════════════════════════════

@test "init: exits 0 on empty directory" {
  run sc init
  [ "$status" -eq 0 ]
}

@test "init: creates product/, agent/, .staircase/tmp/, manifest.json" {
  sc init > /dev/null
  [ -d "product" ]
  [ -d "agent" ]
  [ -d ".staircase/tmp" ]
  [ -f ".staircase/manifest.json" ]
}

@test "init: manifest has correct initial schema" {
  sc init > /dev/null
  run jq -r '.version' ".staircase/manifest.json"
  [ "$output" = "1.0" ]
  run jq '.projects' ".staircase/manifest.json"
  [ "$output" = "{}" ]
}

@test "init: idempotent — second run exits 0 and preserves manifest" {
  sc init > /dev/null
  echo '{"version":"1.0","projects":{"keep":"me"}}' > ".staircase/manifest.json"
  run sc init
  [ "$status" -eq 0 ]
  [[ "$output" == *"already initialized"* ]]
  run jq -r '.projects.keep' ".staircase/manifest.json"
  [ "$output" = "me" ]
}

@test "init: first run outputs 'initialized'" {
  run sc init
  [[ "$output" == *"initialized"* ]]
  [[ "$output" != *"already"* ]]
}

@test "init: output goes to stderr, stdout is clean" {
  run bash -c "'$STAIRCASE' init 2>/dev/null"
  [ -z "$output" ]
}

# ═══════════════════════════════════════════════════════════════════════════════
#  REGISTER
# ═══════════════════════════════════════════════════════════════════════════════

@test "register: exits 0 for new app" {
  sc init > /dev/null
  run sc "register backend"
  [ "$status" -eq 0 ]
  [[ "$output" == *"registered"* ]]
}

@test "register: creates product/ and agent/ subtrees" {
  sc init > /dev/null
  sc "register backend" > /dev/null
  [ -d "product/backend" ]
  [ -d "agent/backend/active" ]
  [ -d "agent/backend/tasks" ]
  [ -d "agent/backend/structure" ]
}

@test "register: adds entry to manifest with registered_at" {
  sc init > /dev/null
  sc "register backend" > /dev/null
  run jq -r '.projects.backend.registered_at' ".staircase/manifest.json"
  [[ "$output" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}T ]]
}

@test "register: duplicate exits 1 with error" {
  sc init > /dev/null
  sc "register backend" > /dev/null
  run sc "register backend"
  [ "$status" -eq 1 ]
  [[ "$output" == *"already registered"* ]]
}

@test "register: missing app name exits 1" {
  sc init > /dev/null
  run sc register
  [ "$status" -eq 1 ]
}

@test "register: outside workspace exits 1" {
  run sc "register backend"
  [ "$status" -eq 1 ]
  [[ "$output" == *"no workspace"* ]]
}

@test "register --symlink: creates symlink and sets manifest flag" {
  sc init > /dev/null
  sc "register backend --symlink" > /dev/null
  [ -L "product/backend/tasks" ]
  run readlink "product/backend/tasks"
  [ "$output" = "../../agent/backend/active" ]
  run jq -r '.projects.backend.symlinkEnabled' ".staircase/manifest.json"
  [ "$output" = "true" ]
}

@test "register: without --symlink does not create symlink" {
  sc init > /dev/null
  sc "register backend" > /dev/null
  [ ! -L "product/backend/tasks" ]
  run jq -r '.projects.backend.symlinkEnabled // "null"' ".staircase/manifest.json"
  [ "$output" = "null" ]
}

# ═══════════════════════════════════════════════════════════════════════════════
#  TASK NEW
# ═══════════════════════════════════════════════════════════════════════════════

@test "task new: exits 0 on registered app" {
  sc init > /dev/null
  sc "register myapp" > /dev/null
  run sc "task new myapp T-001"
  [ "$status" -eq 0 ]
}

@test "task new: creates task directory and active context" {
  scaffold
  [ -d "agent/myapp/tasks/T-001" ]
  [ -f "agent/myapp/active/context.json" ]
}

@test "task new: context.json has correct schema" {
  scaffold
  run jq -r '.taskId' "agent/myapp/active/context.json"
  [ "$output" = "T-001" ]
  run jq -r '.app' "agent/myapp/active/context.json"
  [ "$output" = "myapp" ]
  run jq '.stories' "agent/myapp/active/context.json"
  [ "$output" = "[]" ]
  run jq '.files' "agent/myapp/active/context.json"
  [ "$output" = "[]" ]
  run jq -r '.gitDiff' "agent/myapp/active/context.json"
  [ "$output" = "" ]
  run jq -r '.created' "agent/myapp/active/context.json"
  [[ "$output" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$ ]]
}

@test "task new: sets manifest activeTask" {
  scaffold
  run jq -r '.projects.myapp.activeTask' ".staircase/manifest.json"
  [ "$output" = "T-001" ]
}

@test "task new: second task overwrites activeTask" {
  scaffold
  sc "task new myapp T-002" > /dev/null
  run jq -r '.projects.myapp.activeTask' ".staircase/manifest.json"
  [ "$output" = "T-002" ]
}

@test "task new: unregistered app exits 1" {
  sc init > /dev/null
  run sc "task new ghost T-001"
  [ "$status" -eq 1 ]
  [[ "$output" == *"not registered"* ]]
}

@test "task new: missing args exits 1" {
  sc init > /dev/null
  sc "register myapp" > /dev/null
  run sc "task new myapp"
  [ "$status" -eq 1 ]
}

@test "task new: special characters in task ID produce valid JSON" {
  sc init > /dev/null
  sc "register myapp" > /dev/null
  sc 'task new myapp feat/hello\"world' > /dev/null
  run jq -r '.taskId' "agent/myapp/active/context.json"
  [ "$output" = 'feat/hello"world' ]
}

@test "task new: refreshes symlink when enabled" {
  sc init > /dev/null
  sc "register myapp --symlink" > /dev/null
  sc "task new myapp T-001" > /dev/null
  [ -L "product/myapp/tasks" ]
  run jq -r '.taskId' "product/myapp/tasks/context.json"
  [ "$output" = "T-001" ]
}

# ═══════════════════════════════════════════════════════════════════════════════
#  TASK SWITCH
# ═══════════════════════════════════════════════════════════════════════════════

@test "task switch: exits 0 between two tasks" {
  scaffold
  sc "task new myapp T-002" > /dev/null
  run sc "task switch myapp T-001"
  [ "$status" -eq 0 ]
  [[ "$output" == *"switched"* ]]
}

@test "task switch: updates manifest activeTask" {
  scaffold
  sc "task new myapp T-002" > /dev/null
  sc "task switch myapp T-001" > /dev/null
  run jq -r '.projects.myapp.activeTask' ".staircase/manifest.json"
  [ "$output" = "T-001" ]
}

@test "task switch: saves current context to previous task dir" {
  scaffold
  sc "task new myapp T-002" > /dev/null
  sc "task switch myapp T-001" > /dev/null
  [ -f "agent/myapp/tasks/T-002/context.json" ]
  run jq -r '.taskId' "agent/myapp/tasks/T-002/context.json"
  [ "$output" = "T-002" ]
}

@test "task switch: restores target context with custom data" {
  scaffold
  # Inject custom data into T-001's saved context
  printf '{"taskId":"T-001","app":"myapp","created":"2026-01-01T00:00:00Z","stories":["custom"],"files":["a.js"],"gitDiff":"diff"}\n' \
    > "agent/myapp/tasks/T-001/context.json"
  sc "task new myapp T-002" > /dev/null
  sc "task switch myapp T-001" > /dev/null
  run jq -r '.stories[0]' "agent/myapp/active/context.json"
  [ "$output" = "custom" ]
  run jq -r '.files[0]' "agent/myapp/active/context.json"
  [ "$output" = "a.js" ]
  run jq -r '.gitDiff' "agent/myapp/active/context.json"
  [ "$output" = "diff" ]
}

@test "task switch: non-existent task exits 1 with suggestion" {
  scaffold
  run sc "task switch myapp T-999"
  [ "$status" -eq 1 ]
  [[ "$output" == *"not found"* ]]
  [[ "$output" == *"task new"* ]]
}

@test "task switch: unregistered app exits 1" {
  sc init > /dev/null
  run sc "task switch ghost T-001"
  [ "$status" -eq 1 ]
}

@test "task switch --symlink: enables symlinks one-shot" {
  scaffold
  sc "task new myapp T-002" > /dev/null
  sc "task switch myapp T-001 --symlink" > /dev/null
  [ -L "product/myapp/tasks" ]
  run jq -r '.projects.myapp.symlinkEnabled' ".staircase/manifest.json"
  [ "$output" = "true" ]
  run jq -r '.taskId' "product/myapp/tasks/context.json"
  [ "$output" = "T-001" ]
}

@test "task switch: refreshes existing symlink" {
  sc init > /dev/null
  sc "register myapp --symlink" > /dev/null
  sc "task new myapp T-001" > /dev/null
  sc "task new myapp T-002" > /dev/null
  sc "task switch myapp T-001" > /dev/null
  [ -L "product/myapp/tasks" ]
  run jq -r '.taskId' "product/myapp/tasks/context.json"
  [ "$output" = "T-001" ]
}

# ═══════════════════════════════════════════════════════════════════════════════
#  TASK LIST
# ═══════════════════════════════════════════════════════════════════════════════

@test "task list: shows all tasks with active marker" {
  scaffold
  sc "task new myapp T-002" > /dev/null
  sc "task new myapp T-003" > /dev/null
  run sc "task list myapp"
  [ "$status" -eq 0 ]
  [[ "$output" == *"T-001"* ]]
  [[ "$output" == *"T-002"* ]]
  [[ "$output" == *"T-003"* ]]
  [[ "$output" == *"*"* ]]
}

@test "task list: active task has asterisk, others do not" {
  scaffold
  sc "task new myapp T-002" > /dev/null
  run sc "task list myapp"
  local t002_line t001_line
  t002_line="$(echo "$output" | grep 'T-002')"
  [[ "$t002_line" == *"*"* ]]
  t001_line="$(echo "$output" | grep 'T-001')"
  [[ "$t001_line" != *"*"* ]]
}

@test "task list: unregistered app exits 1" {
  sc init > /dev/null
  run sc "task list ghost"
  [ "$status" -eq 1 ]
}

@test "task list: missing app name exits 1" {
  sc init > /dev/null
  run sc "task list"
  [ "$status" -eq 1 ]
}

@test "task list: empty tasks dir exits 0 with no output" {
  sc init > /dev/null
  sc "register myapp" > /dev/null
  run sc "task list myapp"
  [ "$status" -eq 0 ]
}

# ═══════════════════════════════════════════════════════════════════════════════
#  SYMLINK
# ═══════════════════════════════════════════════════════════════════════════════

@test "symlink enable: creates correct relative symlink" {
  scaffold
  run sc "symlink enable myapp"
  [ "$status" -eq 0 ]
  [ -L "product/myapp/tasks" ]
  run readlink "product/myapp/tasks"
  [ "$output" = "../../agent/myapp/active" ]
}

@test "symlink enable: sets symlinkEnabled in manifest" {
  scaffold
  sc "symlink enable myapp" > /dev/null
  run jq -r '.projects.myapp.symlinkEnabled' ".staircase/manifest.json"
  [ "$output" = "true" ]
}

@test "symlink enable: idempotent — second run exits 0" {
  scaffold
  sc "symlink enable myapp" > /dev/null
  run sc "symlink enable myapp"
  [ "$status" -eq 0 ]
  [[ "$output" == *"already enabled"* ]]
}

@test "symlink enable: context readable through symlink" {
  scaffold
  sc "symlink enable myapp" > /dev/null
  run jq -r '.taskId' "product/myapp/tasks/context.json"
  [ "$output" = "T-001" ]
}

@test "symlink enable: fails if tasks/ is a real directory" {
  scaffold
  mkdir -p "product/myapp/tasks"
  run sc "symlink enable myapp"
  [ "$status" -eq 1 ]
  [[ "$output" == *"not a symlink"* ]]
}

@test "symlink disable: removes symlink and clears manifest" {
  scaffold
  sc "symlink enable myapp" > /dev/null
  run sc "symlink disable myapp"
  [ "$status" -eq 0 ]
  [ ! -L "product/myapp/tasks" ]
  run jq -r '.projects.myapp.symlinkEnabled' ".staircase/manifest.json"
  [ "$output" = "false" ]
}

@test "symlink disable: idempotent — already disabled exits 0" {
  scaffold
  run sc "symlink disable myapp"
  [ "$status" -eq 0 ]
  [[ "$output" == *"already disabled"* ]]
}

@test "symlink status: shows table with correct state" {
  sc init > /dev/null
  sc "register linked --symlink" > /dev/null
  sc "task new linked T-001" > /dev/null
  sc "register plain" > /dev/null
  run sc "symlink status"
  [ "$status" -eq 0 ]
  [[ "$output" == *"APP"* ]]
  [[ "$output" == *"linked"* ]]
  [[ "$output" == *"plain"* ]]
}

@test "symlink: survives task switch cycle" {
  sc init > /dev/null
  sc "register myapp --symlink" > /dev/null
  sc "task new myapp A" > /dev/null
  sc "task new myapp B" > /dev/null
  sc "task switch myapp A" > /dev/null
  sc "task switch myapp B" > /dev/null
  sc "task switch myapp A" > /dev/null
  [ -L "product/myapp/tasks" ]
  [ -d "product/myapp/tasks" ]
  run jq -r '.taskId' "product/myapp/tasks/context.json"
  [ "$output" = "A" ]
}

@test "symlink enable: unregistered app exits 1" {
  sc init > /dev/null
  run sc "symlink enable ghost"
  [ "$status" -eq 1 ]
}

@test "symlink disable: unregistered app exits 1" {
  sc init > /dev/null
  run sc "symlink disable ghost"
  [ "$status" -eq 1 ]
}

@test "symlink: unknown subcommand exits 1" {
  sc init > /dev/null
  run sc "symlink gibberish"
  [ "$status" -eq 1 ]
  [[ "$output" == *"Available"* ]]
}

# ═══════════════════════════════════════════════════════════════════════════════
#  RUN
# ═══════════════════════════════════════════════════════════════════════════════

@test "run: missing product dir exits 1 with error" {
  sc init > /dev/null
  run sc "run ghost"
  [ "$status" -eq 1 ]
  [[ "$output" == *"does not exist"* ]]
}

@test "run: missing context.json exits 1 with hint" {
  sc init > /dev/null
  sc "register myapp" > /dev/null
  run sc "run myapp"
  [ "$status" -eq 1 ]
  [[ "$output" == *"task new"* ]]
}

@test "run --dry-run: prints command without executing" {
  scaffold
  run sc "run --dry-run myapp"
  [ "$status" -eq 0 ]
  [[ "$output" == *"[DRY RUN]"* ]]
  [[ "$output" == *"ralph-tui"* ]]
}

@test "run --dry-run: does not modify context.json" {
  scaffold
  local before
  before="$(cat "agent/myapp/active/context.json")"
  sc "run --dry-run myapp" > /dev/null
  run cat "agent/myapp/active/context.json"
  [ "$output" = "$before" ]
}

@test "run --dry-run --agent-config: prints merge info without writing" {
  scaffold
  local before
  before="$(cat "agent/myapp/active/context.json")"
  run sc 'run --dry-run myapp --agent-config '"'"'{"model":"test"}'"'"''
  [ "$status" -eq 0 ]
  [[ "$output" == *"[DRY RUN]"* ]]
  [[ "$output" == *"agentConfig"* ]]
  local after
  after="$(cat "agent/myapp/active/context.json")"
  [ "$before" = "$after" ]
}

@test "run: missing app name exits 1" {
  sc init > /dev/null
  run sc run
  [ "$status" -eq 1 ]
}

# ═══════════════════════════════════════════════════════════════════════════════
#  LS
# ═══════════════════════════════════════════════════════════════════════════════

@test "ls: no workspace prints info, exits 0" {
  run sc ls
  [ "$status" -eq 0 ]
  [[ "$output" == *"no workspace"* ]]
}

@test "ls: empty workspace prints root path" {
  sc init > /dev/null
  run sc ls
  [ "$status" -eq 0 ]
  [[ "$output" == *"$WORK_DIR"* ]]
}

@test "ls: shows registered apps with tree characters" {
  sc init > /dev/null
  sc "register alpha" > /dev/null
  sc "register bravo" > /dev/null
  run sc ls
  [ "$status" -eq 0 ]
  [[ "$output" == *"alpha"* ]]
  [[ "$output" == *"bravo"* ]]
  [[ "$output" == *"├──"* ]]
  [[ "$output" == *"└──"* ]]
}

@test "ls: shows active task" {
  scaffold
  run sc ls
  [[ "$output" == *"T-001"* ]]
}

@test "ls: shows (none) when no active task" {
  sc init > /dev/null
  sc "register myapp" > /dev/null
  run sc ls
  [[ "$output" == *"(none)"* ]]
}

@test "ls: shows task count" {
  scaffold
  sc "task new myapp T-002" > /dev/null
  sc "task new myapp T-003" > /dev/null
  run sc ls
  [[ "$output" == *"tasks:   3"* ]]
}

@test "ls: shows symlink state" {
  sc init > /dev/null
  sc "register linked --symlink" > /dev/null
  sc "task new linked T-001" > /dev/null
  sc "register plain" > /dev/null
  run sc ls
  [[ "$output" == *"symlink: on"* ]]
  [[ "$output" == *"symlink: off"* ]]
}

@test "ls: survives missing product dir without crash" {
  sc init > /dev/null
  sc "register myapp" > /dev/null
  rm -rf "product/myapp"
  run sc ls
  [ "$status" -eq 0 ]
}

# ═══════════════════════════════════════════════════════════════════════════════
#  STATUS
# ═══════════════════════════════════════════════════════════════════════════════

@test "status: empty workspace shows header, exits 0" {
  sc init > /dev/null
  run bash -c "'$STAIRCASE' status"
  [ "$status" -eq 0 ]
  [[ "$output" == *"APP"* ]]
}

@test "status: shows registered apps and active tasks" {
  scaffold
  run bash -c "'$STAIRCASE' status"
  [ "$status" -eq 0 ]
  [[ "$output" == *"myapp"* ]]
  [[ "$output" == *"T-001"* ]]
}

@test "status: shows (none) for app without active task" {
  sc init > /dev/null
  sc "register myapp" > /dev/null
  run bash -c "'$STAIRCASE' status"
  [[ "$output" == *"(none)"* ]]
}

@test "status --json: output is valid JSON" {
  sc init > /dev/null
  run bash -c "'$STAIRCASE' status --json | jq empty"
  [ "$status" -eq 0 ]
}

@test "status --json: contains registered project" {
  scaffold
  run bash -c "'$STAIRCASE' status --json | jq -r '.projects.myapp.activeTask'"
  [ "$output" = "T-001" ]
}

@test "status: no workspace with --json outputs empty manifest" {
  run bash -c "'$STAIRCASE' status --json | jq -r '.version'"
  [ "$status" -eq 0 ]
  [ "$output" = "1.0" ]
}

# ═══════════════════════════════════════════════════════════════════════════════
#  DOCTOR
# ═══════════════════════════════════════════════════════════════════════════════

@test "doctor: healthy workspace exits 0" {
  scaffold
  run sc doctor
  [ "$status" -eq 0 ]
  [[ "$output" == *"healthy"* ]]
}

@test "doctor: no workspace exits 0 with info" {
  run sc doctor
  [ "$status" -eq 0 ]
  [[ "$output" == *"no workspace"* ]]
}

@test "doctor: missing tmp/ exits 1" {
  sc init > /dev/null
  rm -rf ".staircase/tmp"
  run sc doctor
  [ "$status" -eq 1 ]
  [[ "$output" == *"tmp"* ]]
}

@test "doctor --fix: repairs missing tmp/" {
  sc init > /dev/null
  rm -rf ".staircase/tmp"
  run sc "doctor --fix"
  [ "$status" -eq 0 ]
  [ -d ".staircase/tmp" ]
}

@test "doctor: invalid manifest exits 1" {
  sc init > /dev/null
  echo "broken" > ".staircase/manifest.json"
  run sc doctor
  [ "$status" -eq 1 ]
  [[ "$output" == *"invalid JSON"* ]]
}

@test "doctor --fix: repairs invalid manifest" {
  sc init > /dev/null
  echo "broken" > ".staircase/manifest.json"
  run sc "doctor --fix"
  [ "$status" -eq 0 ]
  run jq empty ".staircase/manifest.json"
  [ "$status" -eq 0 ]
}

@test "doctor: missing product dir exits 1" {
  scaffold
  rm -rf "product/myapp"
  run sc doctor
  [ "$status" -eq 1 ]
}

@test "doctor --fix: deregisters app with missing product path" {
  scaffold
  rm -rf "product/myapp"
  sc "doctor --fix" > /dev/null || true
  # App is removed from manifest
  run jq -r '.projects.myapp // "null"' ".staircase/manifest.json"
  [ "$output" = "null" ]
  # Note: agent/myapp/ remains as an orphan (reported as a separate issue).
  # A second --fix pass does not auto-remove orphaned agent dirs — that's by design.
}

@test "doctor: missing context.json with activeTask exits 1" {
  scaffold
  rm -f "agent/myapp/active/context.json"
  run sc doctor
  [ "$status" -eq 1 ]
  [[ "$output" == *"context.json"* ]]
}

@test "doctor --fix: creates empty context.json for app with activeTask" {
  scaffold
  rm -f "agent/myapp/active/context.json"
  run sc "doctor --fix"
  [ "$status" -eq 0 ]
  [ -f "agent/myapp/active/context.json" ]
}

@test "doctor: detects orphaned agent directory" {
  sc init > /dev/null
  mkdir -p "agent/orphan/active"
  run sc doctor
  [ "$status" -eq 1 ]
  [[ "$output" == *"orphan"* ]]
  [[ "$output" == *"not registered"* ]]
}

@test "doctor: detects missing symlink when enabled" {
  scaffold
  sc "symlink enable myapp" > /dev/null
  rm "product/myapp/tasks"
  run sc doctor
  [ "$status" -eq 1 ]
  [[ "$output" == *"symlink"* ]]
}

@test "doctor --fix: recreates missing symlink" {
  scaffold
  sc "symlink enable myapp" > /dev/null
  rm "product/myapp/tasks"
  run sc "doctor --fix"
  [ "$status" -eq 0 ]
  [ -L "product/myapp/tasks" ]
  run readlink "product/myapp/tasks"
  [ "$output" = "../../agent/myapp/active" ]
}

@test "doctor: detects broken symlink (dangling target)" {
  scaffold
  sc "symlink enable myapp" > /dev/null
  rm "product/myapp/tasks"
  ln -s "../../agent/myapp/nonexistent" "product/myapp/tasks"
  run sc doctor
  [ "$status" -eq 1 ]
  [[ "$output" == *"broken"* ]]
}

@test "doctor --fix: repairs broken symlink" {
  scaffold
  sc "symlink enable myapp" > /dev/null
  rm "product/myapp/tasks"
  ln -s "../../agent/myapp/nonexistent" "product/myapp/tasks"
  run sc "doctor --fix"
  [ "$status" -eq 0 ]
  [ -L "product/myapp/tasks" ]
  [ -d "product/myapp/tasks" ]
}

@test "doctor --fix: repairs multiple issues in one pass" {
  sc init > /dev/null
  sc "register app-a" > /dev/null
  sc "register app-b --symlink" > /dev/null
  sc "task new app-b T-001" > /dev/null
  rm -rf ".staircase/tmp"
  rm "product/app-b/tasks"
  run sc "doctor --fix"
  [ "$status" -eq 0 ]
  [[ "$output" == *"repaired"* ]]
  [ -d ".staircase/tmp" ]
  [ -L "product/app-b/tasks" ]
}

# ═══════════════════════════════════════════════════════════════════════════════
#  EXPORT
# ═══════════════════════════════════════════════════════════════════════════════

@test "export: json produces valid JSON with correct app" {
  scaffold
  run bash -c "'$STAIRCASE' export myapp | jq -r '.app'"
  [ "$status" -eq 0 ]
  [ "$output" = "myapp" ]
}

@test "export: json includes active context" {
  scaffold
  run bash -c "'$STAIRCASE' export myapp | jq -r '.agent.active.taskId'"
  [ "$output" = "T-001" ]
}

@test "export: json includes saved tasks" {
  scaffold
  sc "task new myapp T-002" > /dev/null
  sc "task switch myapp T-001" > /dev/null
  run bash -c "'$STAIRCASE' export myapp | jq -r '.agent.tasks | keys[]'"
  [ "$status" -eq 0 ]
  [[ "$output" == *"T-001"* ]]
  [[ "$output" == *"T-002"* ]]
}

@test "export: json includes exported_at timestamp" {
  scaffold
  run bash -c "'$STAIRCASE' export myapp | jq -r '.exported_at'"
  [[ "$output" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}T ]]
}

@test "export --format tar: creates tarball" {
  scaffold
  sc "export myapp --format tar" > /dev/null 2>&1
  local date_str
  date_str="$(date -u +%Y-%m-%d)"
  [ -f "staircase-export-myapp-${date_str}.tar.gz" ]
}

@test "export --format tar: tarball contains agent dir" {
  scaffold
  sc "export myapp --format tar" > /dev/null 2>&1
  local date_str tarfile
  date_str="$(date -u +%Y-%m-%d)"
  tarfile="staircase-export-myapp-${date_str}.tar.gz"
  run tar tzf "$tarfile"
  [[ "$output" == *"agent/myapp/"* ]]
}

@test "export: unknown app exits 1" {
  sc init > /dev/null
  run sc "export ghost"
  [ "$status" -eq 1 ]
  [[ "$output" == *"not registered"* ]]
}

@test "export: unknown format exits 1" {
  scaffold
  run sc "export myapp --format xml"
  [ "$status" -eq 1 ]
}

@test "export --dry-run: does not create files" {
  scaffold
  run sc "export --dry-run myapp --format tar"
  [ "$status" -eq 0 ]
  [[ "$output" == *"[DRY RUN]"* ]]
  local date_str
  date_str="$(date -u +%Y-%m-%d)"
  [ ! -f "staircase-export-myapp-${date_str}.tar.gz" ]
}

# ═══════════════════════════════════════════════════════════════════════════════
#  HOOKS
# ═══════════════════════════════════════════════════════════════════════════════

@test "hooks install: creates hooks.d/ and git hooks" {
  scaffold
  git -C "product/myapp" init -q
  run sc "hooks install myapp"
  [ "$status" -eq 0 ]
  [ -d "hooks.d" ]
  [ -f "hooks.d/01-format.sh" ]
  [ -f "hooks.d/99-ralph-tui.sh" ]
  [ -f "product/myapp/.git/hooks/pre-commit" ]
  [ -f "product/myapp/.git/hooks/post-merge" ]
}

@test "hooks install: stubs and git hooks are executable" {
  scaffold
  git -C "product/myapp" init -q
  sc "hooks install myapp" > /dev/null
  [ -x "hooks.d/01-format.sh" ]
  [ -x "hooks.d/99-ralph-tui.sh" ]
  [ -x "product/myapp/.git/hooks/pre-commit" ]
  [ -x "product/myapp/.git/hooks/post-merge" ]
}

@test "hooks install: idempotent — guard block appears exactly once" {
  scaffold
  git -C "product/myapp" init -q
  sc "hooks install myapp" > /dev/null
  sc "hooks install myapp" > /dev/null
  sc "hooks install myapp" > /dev/null
  run grep -c '>>> stAirCase hooks <<<' "product/myapp/.git/hooks/pre-commit"
  [ "$output" -eq 1 ]
  run grep -c '>>> stAirCase hooks <<<' "product/myapp/.git/hooks/post-merge"
  [ "$output" -eq 1 ]
}

@test "hooks install: preserves existing hook content" {
  scaffold
  git -C "product/myapp" init -q
  mkdir -p "product/myapp/.git/hooks"
  printf '#!/usr/bin/env bash\necho "my custom hook"\n' > "product/myapp/.git/hooks/pre-commit"
  chmod +x "product/myapp/.git/hooks/pre-commit"
  sc "hooks install myapp" > /dev/null
  run grep "my custom hook" "product/myapp/.git/hooks/pre-commit"
  [ "$status" -eq 0 ]
}

@test "hooks install: without git repo exits 1" {
  scaffold
  run sc "hooks install myapp"
  [ "$status" -eq 1 ]
  [[ "$output" == *".git"* ]]
}

@test "hooks install: unregistered app exits 1" {
  sc init > /dev/null
  run sc "hooks install ghost"
  [ "$status" -eq 1 ]
}

@test "hooks install: missing app name exits 1" {
  sc init > /dev/null
  run sc "hooks install"
  [ "$status" -eq 1 ]
}

# ═══════════════════════════════════════════════════════════════════════════════
#  EXPLAIN
# ═══════════════════════════════════════════════════════════════════════════════

@test "explain init: exits 0 and shows filesystem changes" {
  run sc "explain init"
  [ "$status" -eq 0 ]
  [[ "$output" == *"product/"* ]]
  [[ "$output" == *"agent/"* ]]
  [[ "$output" == *"manifest.json"* ]]
}

@test "explain register: shows directory list and manifest diff" {
  sc init > /dev/null
  run sc "explain register myapp"
  [ "$status" -eq 0 ]
  [[ "$output" == *"product/myapp"* ]]
  [[ "$output" == *"agent/myapp"* ]]
}

@test "explain task new: shows context.json preview" {
  scaffold
  run sc "explain task new myapp US-999"
  [ "$status" -eq 0 ]
  [[ "$output" == *"US-999"* ]]
  [[ "$output" == *"context.json"* ]]
}

@test "explain task switch: shows save/load actions" {
  scaffold
  sc "task new myapp T-002" > /dev/null
  run sc "explain task switch myapp T-001"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Save"* ]]
  [[ "$output" == *"Copy"* ]]
}

@test "explain: does not modify workspace" {
  scaffold
  local manifest_before
  manifest_before="$(cat .staircase/manifest.json)"
  sc "explain task new myapp US-999" > /dev/null
  local manifest_after
  manifest_after="$(cat .staircase/manifest.json)"
  [ "$manifest_before" = "$manifest_after" ]
  [ ! -d "agent/myapp/tasks/US-999" ]
}

@test "explain: missing args exits 1" {
  run sc explain
  [ "$status" -eq 1 ]
}

@test "explain: unsupported command exits 1" {
  sc init > /dev/null
  run sc "explain export"
  [ "$status" -eq 1 ]
  [[ "$output" == *"not implemented"* ]]
}

# ═══════════════════════════════════════════════════════════════════════════════
#  DRY-RUN (global flag)
# ═══════════════════════════════════════════════════════════════════════════════

@test "dry-run: init does not create any files" {
  run sc "init --dry-run"
  [ "$status" -eq 0 ]
  [[ "$output" == *"[DRY RUN]"* ]]
  [ ! -d ".staircase" ]
  [ ! -d "product" ]
}

@test "dry-run: register does not create directories" {
  sc init > /dev/null
  run sc "register --dry-run newapp"
  [ "$status" -eq 0 ]
  [ ! -d "product/newapp" ]
  [ ! -d "agent/newapp" ]
}

@test "dry-run: task new does not create files" {
  scaffold
  run sc "task new --dry-run myapp T-999"
  [ "$status" -eq 0 ]
  [ ! -d "agent/myapp/tasks/T-999" ]
}

@test "dry-run: symlink enable does not create link" {
  scaffold
  run sc "symlink enable --dry-run myapp"
  [ "$status" -eq 0 ]
  [[ "$output" == *"[DRY RUN]"* ]]
  [ ! -L "product/myapp/tasks" ]
}

@test "dry-run: hooks install does not create files" {
  scaffold
  git -C "product/myapp" init -q
  run sc "hooks install --dry-run myapp"
  [ "$status" -eq 0 ]
  [ ! -d "hooks.d" ]
}

@test "dry-run: export tar does not create archive" {
  scaffold
  run sc "export --dry-run myapp --format tar"
  [ "$status" -eq 0 ]
  local date_str
  date_str="$(date -u +%Y-%m-%d)"
  [ ! -f "staircase-export-myapp-${date_str}.tar.gz" ]
}

# ═══════════════════════════════════════════════════════════════════════════════
#  ENVIRONMENT & FLAGS
# ═══════════════════════════════════════════════════════════════════════════════

@test "NO_COLOR: suppresses ANSI escape codes" {
  run bash -c "NO_COLOR=1 '$STAIRCASE' init 2>&1"
  [ "$status" -eq 0 ]
  [[ "$output" != *$'\033['* ]]
}

@test "--version: prints version string" {
  run "$STAIRCASE" --version
  [ "$status" -eq 0 ]
  [[ "$output" == "staircase 1.0.0" ]]
}

@test "--help: prints usage" {
  run bash -c "'$STAIRCASE' --help 2>&1"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Usage:"* ]]
  [[ "$output" == *"Commands:"* ]]
}

@test "unknown command: exits 1 with error and usage" {
  run sc "gibberish"
  [ "$status" -eq 1 ]
  [[ "$output" == *"Unknown command"* ]]
}

@test "unknown task subcommand: exits 1 with available list" {
  sc init > /dev/null
  run sc "task gibberish"
  [ "$status" -eq 1 ]
  [[ "$output" == *"Available"* ]]
}

# ═══════════════════════════════════════════════════════════════════════════════
#  EDGE CASES & INTEGRATION
# ═══════════════════════════════════════════════════════════════════════════════

@test "atomicity: rapid task creates leave manifest valid" {
  scaffold
  for i in $(seq 1 10); do
    sc "task new myapp RAPID-$i" > /dev/null
  done
  run jq empty ".staircase/manifest.json"
  [ "$status" -eq 0 ]
  run jq -r '.projects.myapp.activeTask' ".staircase/manifest.json"
  [ "$output" = "RAPID-10" ]
}

@test "multi-app: independent active tasks" {
  sc init > /dev/null
  sc "register alpha" > /dev/null
  sc "register bravo" > /dev/null
  sc "task new alpha A-001" > /dev/null
  sc "task new bravo B-001" > /dev/null
  sc "task new alpha A-002" > /dev/null
  run jq -r '.projects.alpha.activeTask' ".staircase/manifest.json"
  [ "$output" = "A-002" ]
  run jq -r '.projects.bravo.activeTask' ".staircase/manifest.json"
  [ "$output" = "B-001" ]
  # Switching one doesn't affect the other
  sc "task switch alpha A-001" > /dev/null
  run jq -r '.projects.bravo.activeTask' ".staircase/manifest.json"
  [ "$output" = "B-001" ]
}

@test "multi-app: symlinks are independent per app" {
  sc init > /dev/null
  sc "register alpha --symlink" > /dev/null
  sc "register bravo" > /dev/null
  sc "task new alpha A-001" > /dev/null
  sc "task new bravo B-001" > /dev/null
  [ -L "product/alpha/tasks" ]
  [ ! -L "product/bravo/tasks" ]
  run jq -r '.taskId' "product/alpha/tasks/context.json"
  [ "$output" = "A-001" ]
}

@test "full lifecycle: init → register → tasks → switch → export → doctor" {
  sc init > /dev/null
  sc "register webapp --symlink" > /dev/null
  sc "task new webapp SPRINT-1" > /dev/null
  sc "task new webapp SPRINT-2" > /dev/null
  sc "task switch webapp SPRINT-1" > /dev/null

  # Context is correct via symlink
  run jq -r '.taskId' "product/webapp/tasks/context.json"
  [ "$output" = "SPRINT-1" ]

  # Export works
  run bash -c "'$STAIRCASE' export webapp | jq -r '.agent.active.taskId'"
  [ "$output" = "SPRINT-1" ]

  # Doctor is happy
  run sc doctor
  [ "$status" -eq 0 ]
  [[ "$output" == *"healthy"* ]]
}
