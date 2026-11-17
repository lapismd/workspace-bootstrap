#!/bin/sh
# SPDX-License-Identifier: Apache-2.0

set -eu

repo_root=$(CDPATH='' cd "$(dirname "$0")/.." && pwd -P)
cd "$repo_root"

for script in bootstrap.sh cleanup-workspaces.sh update-guidance.sh lib/common.sh scripts/verify.sh tests/*.sh; do
  sh -n "$script"
done

if command -v shellcheck >/dev/null 2>&1; then
  shellcheck bootstrap.sh cleanup-workspaces.sh update-guidance.sh lib/common.sh scripts/verify.sh tests/*.sh
else
  printf 'warning: shellcheck is not installed; syntax and behavioral tests still run\n' >&2
fi

./tests/test-bootstrap.sh
./tests/test-update-guidance.sh
./tests/test-cleanup.sh
./tests/test-real-jj.sh

printf 'verification passed\n'
