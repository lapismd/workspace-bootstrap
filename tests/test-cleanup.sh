#!/bin/sh
# SPDX-License-Identifier: Apache-2.0

set -eu

repo_root=$(CDPATH='' cd "$(dirname "$0")/.." && pwd -P)
temporary=$(mktemp -d "${TMPDIR:-/tmp}/cleanup-test.XXXXXX")
trap 'rm -rf "$temporary"' EXIT HUP INT TERM

fail() {
  printf 'cleanup test failed: %s\n' "$*" >&2
  exit 1
}

target=$temporary/target
mkdir "$target"

if (cd "$repo_root" && ./cleanup-workspaces.sh --target-root "$target" --purge ../escape) \
  >"$temporary/escape.out" 2>&1; then
  fail "unsafe batch ID unexpectedly succeeded"
fi
grep -q 'invalid batch ID' "$temporary/escape.out" || fail "unsafe batch diagnostic missing"

if (cd "$repo_root" && ./cleanup-workspaces.sh --target-root "$target") \
  >"$temporary/missing.out" 2>&1; then
  fail "missing canonical repositories unexpectedly passed"
fi
grep -q 'repository_failures=24' "$temporary/missing.out" || fail "missing repository count was not reported"

printf 'cleanup boundary tests passed\n'
