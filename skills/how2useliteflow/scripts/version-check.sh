#!/bin/sh
# Check whether the installed copy of this skill is behind the published version.
# Never blocks the skill's normal work: network or parse failures exit 1 quietly.
# Results are cached once per day; repeated runs on the same day replay the cache.
#
# Exit codes:
#   0  installed copy is up to date
#   2  a newer version is available
#   1  check failed (offline, remote unreachable, version unparsable)
#
# Note: exit code 2 means "block" in some agent hook systems. When wiring this
# script into an agent hook, append "|| true" so an available update is never
# treated as a block.

set -eu

SKILL_DIR="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
SKILL_MD="$SKILL_DIR/SKILL.md"
REMOTE_URL="${HOW2USELITEFLOW_SKILL_URL:-https://raw.githubusercontent.com/bryan31/How2useLiteFlow/main/skills/how2useliteflow/SKILL.md}"
TIMEOUT="${HOW2USELITEFLOW_CHECK_TIMEOUT:-8}"
CACHE_DIR="${HOW2USELITEFLOW_CACHE:-$HOME/.cache/how2useliteflow}"
STAMP="$CACHE_DIR/version-check.stamp"
RESULT="$CACHE_DIR/version-check.result"

extract_version() {
  sed -n 's/^[[:space:]]*version:[[:space:]]*"\{0,1\}\([^"]\{1,\}\)"\{0,1\}[[:space:]]*$/\1/p' | head -n 1
}

# version_gt <a> <b>: true if a is a higher dotted-numeric version than b.
version_gt() {
  [ "$1" != "$2" ] || return 1
  awk -v a="$1" -v b="$2" 'BEGIN {
    na = split(a, va, "."); nb = split(b, vb, ".");
    n = (na > nb ? na : nb);
    for (i = 1; i <= n; i++) {
      x = va[i] + 0; y = vb[i] + 0;
      if (x > y) exit 0;
      if (x < y) exit 1;
    }
    exit 1;
  }'
}

fetch_remote() {
  if command -v curl >/dev/null 2>&1; then
    curl -fsL --max-time "$TIMEOUT" -- "$REMOTE_URL" 2>/dev/null
  elif command -v wget >/dev/null 2>&1; then
    wget -q -T "$TIMEOUT" -O - -- "$REMOTE_URL" 2>/dev/null
  else
    return 1
  fi
}

run_check() {
  local_version="$(extract_version <"$SKILL_MD" 2>/dev/null || true)"
  [ -n "$local_version" ] || { echo "version-check: cannot read version from $SKILL_MD" >&2; return 1; }

  remote_md="$(fetch_remote)" || { echo "version-check: remote check unavailable (offline or blocked)" >&2; return 1; }
  remote_version="$(printf '%s\n' "$remote_md" | extract_version)"
  [ -n "$remote_version" ] || { echo "version-check: remote SKILL.md has no version field" >&2; return 1; }

  if version_gt "$remote_version" "$local_version"; then
    printf '本 skill 有新版本：本地 %s → 远端 %s\n' "$local_version" "$remote_version"
    printf '%s\n' '全局安装更新命令：npx skills update how2useliteflow -g -y'
    printf '%s\n' '项目安装更新命令：npx skills update how2useliteflow -p -y'
    return 2
  fi

  printf 'how2useliteflow 已是最新（%s）\n' "$local_version"
  return 0
}

today="$(date +%F)"

# Replay today's cached result when present.
if [ "${HOW2USELITEFLOW_CHECK_FORCE:-0}" != "1" ] && [ -f "$STAMP" ] && [ -f "$RESULT" ] \
  && [ "$(cat "$STAMP" 2>/dev/null || true)" = "$today" ]; then
  cached_code="$(sed -n '1p' "$RESULT")"
  sed -n '2,$p' "$RESULT"
  exit "$cached_code"
fi

if out="$(run_check)"; then code=0; else code=$?; fi

mkdir -p "$CACHE_DIR" 2>/dev/null || true
{
  printf '%s\n' "$code"
  printf '%s\n' "$out"
} >"$RESULT" 2>/dev/null || true
printf '%s\n' "$today" >"$STAMP" 2>/dev/null || true

if [ -n "$out" ]; then
  printf '%s\n' "$out"
fi
exit "$code"
