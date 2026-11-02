#!/bin/sh
# SPDX-License-Identifier: Apache-2.0

set -eu

repo_root=$(CDPATH='' cd "$(dirname "$0")/.." && pwd -P)
temporary=$(mktemp -d "${TMPDIR:-/tmp}/real-jj-test.XXXXXX")
trap 'rm -rf "$temporary"' EXIT HUP INT TERM
target=$temporary/target
source_repo=$temporary/source
manifest=$temporary/repositories.tsv
mkdir "$target"

fail() {
  printf 'real JJ test failed: %s\n' "$*" >&2
  exit 1
}

cat >"$manifest" <<'EOF'
# repository<TAB>destination<TAB>profiles<TAB>trunk
test/example	canonical	active,all	main
EOF

jj git init --colocate "$source_repo" >/dev/null
printf 'base\n' >"$source_repo/base.txt"
jj -R "$source_repo" commit -m 'Create base fixture' >/dev/null
jj -R "$source_repo" bookmark create main -r @- >/dev/null
jj git clone "$source_repo" "$target/canonical" >/dev/null
jj -R "$target/canonical" git remote set-url origin git@github.com:test/example.git

run_cleanup() {
  (cd "$repo_root" && \
    WB_MANIFEST="$manifest" WB_EXPECT_ACTIVE=1 WB_EXPECT_ALL=1 \
    ./cleanup-workspaces.sh --target-root "$target" "$@")
}

jj -R "$target/canonical" workspace add "$target/integrated" --name integrated \
  -r main@origin -m 'Integrated fixture workspace' >/dev/null

preview=$(run_cleanup)
printf '%s\n' "$preview" | grep -q 'eligible test/example/integrated' || fail "integrated workspace was not eligible"

applied=$(run_cleanup --apply)
batch=$(printf '%s\n' "$applied" | sed -n 's/^quarantine batch: //p')
[ -n "$batch" ] || fail "quarantine batch ID missing"
[ ! -e "$target/integrated" ] || fail "quarantined workspace remained at original path"
[ -d "$target/.workspace-quarantine/$batch/test/example/integrated" ] || fail "quarantine directory missing"

run_cleanup --restore "$batch" >"$temporary/restore-preview.out"
[ ! -e "$target/integrated" ] || fail "restore preview changed files"
run_cleanup --restore "$batch" --apply >/dev/null
[ -d "$target/integrated" ] || fail "restore did not return workspace"

applied=$(run_cleanup --apply)
batch=$(printf '%s\n' "$applied" | sed -n 's/^quarantine batch: //p')
run_cleanup --purge "$batch" >"$temporary/purge-preview.out"
[ -d "$target/.workspace-quarantine/$batch/test/example/integrated" ] || fail "purge preview deleted files"
run_cleanup --purge "$batch" --apply >/dev/null
[ ! -e "$target/.workspace-quarantine/$batch" ] || fail "purge retained batch"
if jj -R "$target/canonical" --ignore-working-copy workspace list | grep -q '^integrated:'; then
  fail "purge retained workspace registration"
fi

jj -R "$target/canonical" workspace add "$target/unintegrated" --name unintegrated \
  -r main@origin -m 'Unintegrated fixture workspace' >/dev/null
printf 'unique\n' >"$target/unintegrated/unique.txt"
jj -R "$target/unintegrated" commit -m 'Create unique fixture change' >/dev/null
blocked=$(run_cleanup)
printf '%s\n' "$blocked" | grep -q 'unintegrated: contains commits not integrated by exact ancestry' ||
  fail "unique commit was not blocked"

jj -R "$target/canonical" workspace add "$target/dirty" --name dirty \
  -r main@origin -m 'Dirty fixture workspace' >/dev/null
printf 'dirty\n' >"$target/dirty/dirty.txt"
blocked=$(run_cleanup)
printf '%s\n' "$blocked" | grep -q 'dirty: tracked or untracked working-copy changes' ||
  fail "dirty workspace was not blocked"

jj -R "$target/canonical" workspace add "$target/protected" --name protected \
  -r main@origin -m 'Protected fixture workspace' >/dev/null
jj -R "$target/canonical" bookmark create protect -r 'protected@' >/dev/null
blocked=$(run_cleanup)
printf '%s\n' "$blocked" | grep -q 'protected: workspace-only commit has a local bookmark' ||
  fail "bookmarked workspace was not blocked"

jj -R "$target/canonical" workspace add "$temporary/external" --name external \
  -r main@origin -m 'External fixture workspace' >/dev/null
blocked=$(run_cleanup)
printf '%s\n' "$blocked" | grep -q 'external: outside the direct sibling cleanup boundary' ||
  fail "external workspace was not blocked"

printf 'real JJ tests passed\n'
