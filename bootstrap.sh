#!/bin/sh
# SPDX-License-Identifier: Apache-2.0

set -u

WB_REPO_ROOT=$(CDPATH='' cd "$(dirname "$0")" && pwd -P) || exit 1
WB_MANIFEST=${WB_MANIFEST:-$WB_REPO_ROOT/repositories.tsv}
export WB_REPO_ROOT WB_MANIFEST
. "$WB_REPO_ROOT/lib/common.sh"

usage() {
  cat <<'EOF'
Usage: ./bootstrap.sh [options]

Clone and verify the LapisMD sibling workspace.

Options:
  --profile active|all   Repository profile (default: active)
  --target-root PATH     Parent directory for sibling repositories
  --config-only          Install or verify root configuration only
  --dry-run              Report actions without changing files
  --list                 List selected manifest entries and exit
  --help                 Show this help
EOF
}

profile=active
target_root=
config_only=false
dry_run=false
list_only=false

while [ "$#" -gt 0 ]; do
  case $1 in
    --profile)
      [ "$#" -ge 2 ] || wb_die "--profile requires a value"
      profile=$2
      shift 2
      ;;
    --target-root)
      [ "$#" -ge 2 ] || wb_die "--target-root requires a path"
      target_root=$2
      shift 2
      ;;
    --config-only) config_only=true; shift ;;
    --dry-run) dry_run=true; shift ;;
    --list) list_only=true; shift ;;
    --help) usage; exit 0 ;;
    *) wb_die "unknown argument: $1" ;;
  esac
done

wb_require_repo_root
wb_validate_profile "$profile"
wb_validate_manifest

if [ -z "$target_root" ]; then
  target_root=$(dirname "$WB_REPO_ROOT")
fi
target_root=$(wb_resolve_dir "$target_root") || wb_die "target root does not exist: $target_root"

if $list_only; then
  printf 'repository\tdestination\tprofiles\ttrunk\n'
  wb_manifest_rows "$profile"
  exit 0
fi

if [ ! -w "$target_root" ] && ! $dry_run; then
  wb_die "target root is not writable: $target_root"
fi

config_conflicts=0
config_missing=0

check_config() {
  source_file=$1
  destination=$2
  label=$3

  if [ -e "$destination" ]; then
    if [ ! -f "$destination" ] || [ -L "$destination" ]; then
      wb_error "$label destination is not a regular file: $destination"
      config_conflicts=$((config_conflicts + 1))
    elif cmp -s "$source_file" "$destination"; then
      wb_info "config verified: $destination"
    else
      wb_error "$label differs from the portable template: $destination"
      config_conflicts=$((config_conflicts + 1))
    fi
  else
    wb_info "config missing: $destination"
    config_missing=$((config_missing + 1))
  fi
}

install_config() {
  source_file=$1
  destination=$2
  destination_dir=$(dirname "$destination")

  if [ -e "$destination" ]; then
    return 0
  fi
  if $dry_run; then
    wb_info "would install config: $destination"
    return 0
  fi
  mkdir -p "$destination_dir" || return 1
  temporary="$destination.tmp.$$"
  cp "$source_file" "$temporary" || return 1
  chmod 0644 "$temporary" || return 1
  mv "$temporary" "$destination" || return 1
  wb_info "config installed: $destination"
}

agents_source=$WB_REPO_ROOT/templates/workspace/AGENTS.md
cursor_source=$WB_REPO_ROOT/templates/workspace/.cursor/rules/commit-after-change.mdc
agents_destination=$target_root/AGENTS.md
cursor_destination=$target_root/.cursor/rules/commit-after-change.mdc

check_config "$agents_source" "$agents_destination" "Codex AGENTS.md"
check_config "$cursor_source" "$cursor_destination" "Cursor rule"
[ "$config_conflicts" -eq 0 ] || wb_die "root configuration conflict; no files were changed"

install_config "$agents_source" "$agents_destination" || wb_die "failed to install $agents_destination"
install_config "$cursor_source" "$cursor_destination" || wb_die "failed to install $cursor_destination"

if $config_only; then
  exit 0
fi

wb_require_command git
wb_require_command jj

selected=$(mktemp "${TMPDIR:-/tmp}/workspace-bootstrap.XXXXXX") || wb_die "cannot create temporary file"
trap 'rm -f "$selected"' EXIT HUP INT TERM
wb_manifest_rows "$profile" >"$selected"

cloned=0
verified=0
initialized=0
failed=0

tab=$(printf '\t')
while IFS="$tab" read -r repository destination _profiles _trunk; do
  [ -n "$repository" ] || continue
  checkout=$target_root/$destination
  clone_url=git@github.com:$repository.git

  if [ -e "$checkout" ]; then
    if [ ! -d "$checkout" ] || [ -L "$checkout" ]; then
      wb_error "$repository: destination is not a regular directory: $checkout"
      failed=$((failed + 1))
      continue
    fi
    if ! remote=$(wb_matching_remote "$checkout" "$repository"); then
      wb_error "$repository: existing directory has no matching GitHub remote: $checkout"
      failed=$((failed + 1))
      continue
    fi
    wb_info "$repository: verified existing checkout via remote $remote"
    verified=$((verified + 1))
  else
    if $dry_run; then
      wb_info "$repository: would clone $clone_url into $checkout"
      cloned=$((cloned + 1))
      wb_info "$repository: would initialize colocated JJ"
      initialized=$((initialized + 1))
      continue
    fi
    if ! git clone "$clone_url" "$checkout"; then
      wb_error "$repository: clone failed"
      failed=$((failed + 1))
      continue
    fi
    cloned=$((cloned + 1))
  fi

  if [ -e "$checkout/.jj" ]; then
    if jj -R "$checkout" root >/dev/null 2>&1; then
      wb_info "$repository: colocated JJ verified"
    else
      wb_error "$repository: .jj exists but is not a valid JJ workspace"
      failed=$((failed + 1))
    fi
  elif $dry_run; then
    wb_info "$repository: would initialize colocated JJ"
    initialized=$((initialized + 1))
  elif jj git init --colocate "$checkout" >/dev/null; then
    wb_info "$repository: initialized colocated JJ"
    initialized=$((initialized + 1))
  else
    wb_error "$repository: JJ initialization failed"
    failed=$((failed + 1))
  fi
done <"$selected"

printf 'summary: cloned=%d verified=%d initialized=%d failed=%d\n' \
  "$cloned" "$verified" "$initialized" "$failed"

[ "$failed" -eq 0 ]
