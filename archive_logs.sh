#!/usr/bin/env bash
set -uo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
GIT_REPO="${GIT_REPO:-$SCRIPT_DIR}"
LOG_SOURCE="${LOG_SOURCE:-$(dirname "$GIT_REPO")/goblin/data/logs}"
ARCHIVE_ROOT="${ARCHIVE_ROOT:-$GIT_REPO/logs}"
COPY_SCRIPT="${COPY_SCRIPT:-$GIT_REPO/copy_active_logs.py}"
SPLIT_SCRIPT="${SPLIT_SCRIPT:-$GIT_REPO/split_large_logs.py}"
SLEEP_SECONDS="${SLEEP_SECONDS:-1800}"
MAX_FILE_BYTES="${MAX_FILE_BYTES:-47185920}"
GITHUB_HARD_LIMIT_BYTES="${GITHUB_HARD_LIMIT_BYTES:-104857600}"

RUN_ONCE=false
if [[ "${1:-}" == "--once" ]]; then
  RUN_ONCE=true
elif [[ -n "${1:-}" ]]; then
  echo "Usage: $0 [--once]" >&2
  exit 2
fi

log() { printf '[%s] %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*"; }

archive_once() {
  local today timestamp day_dir oversized_file
  today="$(date '+%Y-%m-%d')"
  timestamp="$(date '+%Y-%m-%d_%H-%M-%S')"
  day_dir="$ARCHIVE_ROOT/$today"

  log "Starting Goblin! logs archive job"
  log "Source: $LOG_SOURCE"
  log "Destination: $day_dir"

  command -v git >/dev/null 2>&1 || { log "ERROR: git not found"; return 1; }
  command -v python3 >/dev/null 2>&1 || { log "ERROR: python3 not found"; return 1; }

  [[ -d "$LOG_SOURCE" ]] || { log "ERROR: LOG_SOURCE does not exist: $LOG_SOURCE"; return 1; }
  [[ -d "$GIT_REPO/.git" ]] || { log "ERROR: not a Git repository: $GIT_REPO"; return 1; }
  [[ -f "$COPY_SCRIPT" ]] || { log "ERROR: missing $COPY_SCRIPT"; return 1; }
  [[ -f "$SPLIT_SCRIPT" ]] || { log "ERROR: missing $SPLIT_SCRIPT"; return 1; }

  mkdir -p "$day_dir"

  python3 "$COPY_SCRIPT" --source "$LOG_SOURCE" --destination "$day_dir" || return 1
  python3 "$SPLIT_SCRIPT" --root "$day_dir" --max-bytes "$MAX_FILE_BYTES" || return 1

  oversized_file="$(
    find "$GIT_REPO" -path "$GIT_REPO/.git" -prune -o       -type f -size +"${GITHUB_HARD_LIMIT_BYTES}"c -print -quit
  )"
  [[ -z "$oversized_file" ]] || {
    log "ERROR: file still exceeds 100 MiB: $oversized_file"
    return 1
  }

  cd "$GIT_REPO" || return 1

  if [[ -n "$(git status --porcelain -- logs)" ]]; then
    git add -A -- logs
    if ! git diff --cached --quiet; then
      git commit -m "logs - $timestamp" || return 1
    fi
  else
    log "No new log changes to commit."
  fi

  git push || {
    log "ERROR: git push failed. The next cycle will retry."
    return 1
  }

  log "Done: logs pushed successfully."
}

trap 'log "Stopping Goblin! log archiver."; exit 0' INT TERM

while true; do
  archive_once || log "Archive cycle completed with errors."
  [[ "$RUN_ONCE" == true ]] && break
  log "Waiting $SLEEP_SECONDS seconds before next run..."
  sleep "$SLEEP_SECONDS"
done
