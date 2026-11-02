#!/bin/sh
# SPDX-License-Identifier: Apache-2.0

set -eu

repo_root=$(CDPATH='' cd "$(dirname "$0")/.." && pwd -P)
temporary=$(mktemp -d "${TMPDIR:-/tmp}/bootstrap-test.XXXXXX")
trap 'rm -rf "$temporary"' EXIT HUP INT TERM
fake_bin=$temporary/bin
mkdir -p "$fake_bin"

cat >"$fake_bin/git" <<'EOF'
#!/bin/sh
set -eu
if [ "$1" = clone ]; then
  url=$2
  destination=$3
  case $url in
    *"${FAKE_GIT_FAIL:-__never__}"*) exit 31 ;;
  esac
  mkdir -p "$destination/.git"
  printf '%s\n' "$url" >"$destination/.fake-origin"
  exit 0
fi
if [ "$1" = -C ]; then
  checkout=$2
  shift 2
  if [ "$1" = remote ] && [ "$#" -eq 1 ]; then
    printf 'upstream\n'
    exit 0
  fi
  case "$1 ${2:-}" in
    "rev-parse --git-dir")
      [ -d "$checkout/.git" ] && { printf '.git\n'; exit 0; }
      exit 1
      ;;
    "remote get-url")
      cat "$checkout/.fake-origin"
      exit 0
      ;;
  esac
fi
exit 2
EOF

cat >"$fake_bin/jj" <<'EOF'
#!/bin/sh
set -eu
if [ "$1" = git ] && [ "$2" = init ] && [ "$3" = --colocate ]; then
  mkdir -p "$4/.jj"
  exit 0
fi
if [ "$1" = -R ] && [ "$3" = root ]; then
  [ -d "$2/.jj" ]
  exit $?
fi
exit 2
EOF
chmod +x "$fake_bin/git" "$fake_bin/jj"

fail() {
  printf 'bootstrap test failed: %s\n' "$*" >&2
  exit 1
}

run_bootstrap() {
  target=$1
  shift
  (cd "$repo_root" && PATH="$fake_bin:$PATH" ./bootstrap.sh --target-root "$target" "$@")
}

list_output=$(cd "$repo_root" && ./bootstrap.sh --list)
active_count=$(printf '%s\n' "$list_output" | awk 'NR > 1 { count++ } END { print count + 0 }')
[ "$active_count" -eq 22 ] || fail "active list count was $active_count"
all_count=$(cd "$repo_root" && ./bootstrap.sh --profile all --list | awk 'NR > 1 { count++ } END { print count + 0 }')
[ "$all_count" -eq 30 ] || fail "all list count was $all_count"

dry_root=$temporary/dry
mkdir "$dry_root"
dry_output=$(run_bootstrap "$dry_root" --dry-run)
printf '%s\n' "$dry_output" | grep -q 'summary: cloned=22 verified=0 initialized=22 failed=0' ||
  fail "unexpected dry-run summary"
[ ! -e "$dry_root/lapis-notes" ] || fail "dry run created a checkout"
[ ! -e "$dry_root/AGENTS.md" ] || fail "dry run installed configuration"

config_root=$temporary/config-only
mkdir "$config_root"
run_bootstrap "$config_root" --config-only >/dev/null
[ -f "$config_root/AGENTS.md" ] || fail "config-only did not install AGENTS.md"
[ ! -e "$config_root/lapis-notes" ] || fail "config-only cloned a repository"

fresh_root=$temporary/fresh
mkdir "$fresh_root"
run_bootstrap "$fresh_root" >"$temporary/first.out"
[ -d "$fresh_root/lapis-notes/.jj" ] || fail "fresh clone did not initialize JJ"
cmp "$repo_root/templates/workspace/AGENTS.md" "$fresh_root/AGENTS.md" || fail "AGENTS template mismatch"
cmp "$repo_root/templates/workspace/.cursor/rules/commit-after-change.mdc" \
  "$fresh_root/.cursor/rules/commit-after-change.mdc" || fail "Cursor template mismatch"
grep -q 'summary: cloned=22 verified=0 initialized=22 failed=0' "$temporary/first.out" ||
  fail "unexpected first-run summary"

printf 'https://github.com/lapismd/lapis-notes.git\n' >"$fresh_root/lapis-notes/.fake-origin"
run_bootstrap "$fresh_root" >"$temporary/second.out"
grep -q 'summary: cloned=0 verified=22 initialized=0 failed=0' "$temporary/second.out" ||
  fail "rerun was not idempotent"

conflict_root=$temporary/conflict
mkdir "$conflict_root"
printf 'custom\n' >"$conflict_root/AGENTS.md"
if run_bootstrap "$conflict_root" >"$temporary/conflict.out" 2>&1; then
  fail "configuration conflict unexpectedly succeeded"
fi
[ ! -e "$conflict_root/lapis-notes" ] || fail "clone occurred after configuration conflict"

failure_root=$temporary/failure
mkdir "$failure_root"
if FAKE_GIT_FAIL=lapis-desktop run_bootstrap "$failure_root" >"$temporary/failure.out" 2>&1; then
  fail "clone failure unexpectedly succeeded"
fi
grep -q 'failed=1' "$temporary/failure.out" || fail "clone failure was not summarized"
[ -d "$failure_root/jj-acp/.jj" ] || fail "bootstrap did not continue after a clone failure"

printf 'bootstrap tests passed\n'
