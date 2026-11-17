#!/bin/sh
# SPDX-License-Identifier: Apache-2.0

set -eu

repo_root=$(CDPATH='' cd "$(dirname "$0")/.." && pwd -P)
temporary=$(mktemp -d "${TMPDIR:-/tmp}/guidance-test.XXXXXX")
trap 'rm -rf "$temporary"' EXIT HUP INT TERM
target="$temporary/main workspace"
mkdir "$target"

fail() {
  printf 'guidance test failed: %s\n' "$*" >&2
  exit 1
}

update() {
  (cd "$temporary" && "$repo_root/update-guidance.sh" --target-root "$target" "$@")
}

printf 'local guidance\n' >"$target/AGENTS.md"
cp "$target/AGENTS.md" "$temporary/original"
update >"$temporary/preview.out"
cmp "$temporary/original" "$target/AGENTS.md" || fail "preview changed guidance"
[ "$(find "$target" -print | wc -l | tr -d ' ')" -eq 2 ] || fail "preview created files"
grep -q 'would update' "$temporary/preview.out" || fail "preview diagnostic missing"

update --apply >"$temporary/apply.out"
cmp "$repo_root/templates/workspace/AGENTS.md" "$target/AGENTS.md" || fail "template not installed"
set -- "$target"/AGENTS.md.backup.*
[ "$#" -eq 1 ] && [ -f "$1" ] || fail "expected one backup"
cmp "$temporary/original" "$1" || fail "backup lost original guidance"

update --apply >"$temporary/again.out"
grep -q 'already up to date' "$temporary/again.out" || fail "rerun was not idempotent"
set -- "$target"/AGENTS.md.backup.*
[ "$#" -eq 1 ] || fail "rerun created another backup"

rm "$target/AGENTS.md"
update >/dev/null
[ ! -e "$target/AGENTS.md" ] || fail "preview installed missing guidance"
update --apply >/dev/null
cmp "$repo_root/templates/workspace/AGENTS.md" "$target/AGENTS.md" || fail "missing guidance not installed"

rm "$target/AGENTS.md"
ln -s "$temporary/original" "$target/AGENTS.md"
if update --apply >"$temporary/symlink.out" 2>&1; then
  fail "symlink unexpectedly accepted"
fi
cmp "$temporary/original" "$target/AGENTS.md" || fail "symlink target changed"
rm "$target/AGENTS.md"
mkdir "$target/AGENTS.md"
if update --apply >/dev/null 2>&1; then
  fail "directory unexpectedly accepted"
fi
if "$repo_root/update-guidance.sh" --target-root "$repo_root" --apply >/dev/null 2>&1; then
  fail "updater accepted its own source repository"
fi
if update --unknown >/dev/null 2>&1; then
  fail "unknown option unexpectedly accepted"
fi

grep -Fq 'jj --config signing.behavior=drop commit -m' \
  "$repo_root/templates/workspace/AGENTS.md" || fail "signing fallback missing"

printf 'guidance update tests passed\n'
