#!/bin/sh
# SPDX-License-Identifier: Apache-2.0

set -eu

WB_REPO_ROOT=$(CDPATH='' cd "$(dirname "$0")" && pwd -P)
. "$WB_REPO_ROOT/lib/common.sh"

usage() {
  cat <<'EOF'
Usage: ./update-guidance.sh [options]

Refresh shared AGENTS.md from the tracked workspace template.
Preview is the default; --apply saves a backup before replacing existing guidance.

Options:
  --target-root PATH   Workspace root (default: parent of this checkout)
  --apply              Install the template, backing up a differing existing file
  --dry-run            Preview only (the default)
  --help               Show this help
EOF
}

target_root=$(dirname "$WB_REPO_ROOT")
apply=false
while [ "$#" -gt 0 ]; do
  case $1 in
    --target-root)
      [ "$#" -ge 2 ] || wb_die "--target-root requires a path"
      target_root=$2
      shift 2
      ;;
    --apply) apply=true; shift ;;
    --dry-run) apply=false; shift ;;
    --help) usage; exit 0 ;;
    *) wb_die "unknown argument: $1" ;;
  esac
done

target_root=$(wb_resolve_dir "$target_root") || wb_die "target root does not exist: $target_root"
case $target_root/ in
  "$WB_REPO_ROOT/"*) wb_die "target root must be outside the bootstrap source repository" ;;
esac
source_file=$WB_REPO_ROOT/templates/workspace/AGENTS.md
destination=$target_root/AGENTS.md
[ -f "$source_file" ] || wb_die "workspace template is missing: $source_file"
[ ! -L "$destination" ] || wb_die "refusing symlink: $destination"
if [ -e "$destination" ] && [ ! -f "$destination" ]; then
  wb_die "guidance is not a regular file: $destination"
fi
if [ -f "$destination" ] && cmp -s "$source_file" "$destination"; then
  wb_info "$destination: already up to date"
  exit 0
fi

if ! $apply; then
  wb_info "$destination: would update from $source_file (use --apply)"
  if [ -f "$destination" ]; then
    diff -u "$destination" "$source_file" || [ "$?" -eq 1 ]
  fi
  exit 0
fi

pending=$(mktemp "$target_root/.AGENTS.md.update.XXXXXX")
trap 'rm -f "$pending"' EXIT HUP INT TERM
if [ -f "$destination" ]; then
  backup=$(mktemp "$target_root/AGENTS.md.backup.XXXXXX")
  cp -p "$destination" "$backup"
  wb_info "backup: $backup"
  cp -p "$destination" "$pending"
else
  chmod 644 "$pending"
fi
cat "$source_file" >"$pending"
mv -f "$pending" "$destination"
wb_info "updated: $destination"
