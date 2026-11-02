#!/bin/sh
# SPDX-License-Identifier: Apache-2.0

set -u

WB_REPO_ROOT=$(CDPATH='' cd "$(dirname "$0")" && pwd -P) || exit 1
WB_MANIFEST=${WB_MANIFEST:-$WB_REPO_ROOT/repositories.tsv}
export WB_REPO_ROOT WB_MANIFEST
. "$WB_REPO_ROOT/lib/common.sh"

usage() {
  cat <<'EOF'
Usage: ./cleanup-workspaces.sh [options]

Preview, quarantine, restore, or purge integrated sibling JJ workspaces.

Options:
  --profile active|all   Canonical repositories to scan (default: active)
  --target-root PATH     Parent directory containing sibling repositories
  --apply                Apply the selected quarantine/restore/purge operation
  --restore BATCH_ID     Restore an entire quarantine batch
  --purge BATCH_ID       Permanently purge an entire quarantine batch
  --help                 Show this help

Without --apply every operation is a preview. Cleanup never fetches remotes.
EOF
}

profile=active
target_root=
apply=false
operation=scan
batch_id=

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
    --apply) apply=true; shift ;;
    --restore)
      [ "$#" -ge 2 ] || wb_die "--restore requires a batch ID"
      [ "$operation" = scan ] || wb_die "choose only one batch operation"
      operation=restore
      batch_id=$2
      shift 2
      ;;
    --purge)
      [ "$#" -ge 2 ] || wb_die "--purge requires a batch ID"
      [ "$operation" = scan ] || wb_die "choose only one batch operation"
      operation=purge
      batch_id=$2
      shift 2
      ;;
    --help) usage; exit 0 ;;
    *) wb_die "unknown argument: $1" ;;
  esac
done

wb_require_repo_root
wb_validate_profile "$profile"
wb_validate_manifest
wb_require_command git
wb_require_command jj

if [ -z "$target_root" ]; then
  target_root=$(dirname "$WB_REPO_ROOT")
fi
target_root=$(wb_resolve_dir "$target_root") || wb_die "target root does not exist: $target_root"
quarantine_root=$target_root/.workspace-quarantine

temporary_root=$(mktemp -d "${TMPDIR:-/tmp}/workspace-cleanup.XXXXXX") ||
  wb_die "cannot create temporary directory"
trap 'rm -rf "$temporary_root"' EXIT HUP INT TERM
tab=$(printf '\t')

workspace_rows() {
  canonical=$1
  jj -R "$canonical" --ignore-working-copy workspace list \
    -T 'name ++ "\t" ++ root ++ "\t" ++ target.commit_id() ++ "\n"'
}

registration_target() {
  canonical=$1
  workspace=$2
  workspace_rows "$canonical" 2>/dev/null |
    awk -F '\t' -v workspace="$workspace" '$1 == workspace { print $3; found = 1 } END { exit(!found) }'
}

remove_empty_batch_dirs() {
  directory=$1
  [ -d "$directory" ] || return 0
  find "$directory" -depth -type d -exec rmdir {} \; 2>/dev/null || true
}

rollback_moves() {
  log=$1
  reversed=$temporary_root/reversed.$$
  awk '{ lines[NR] = $0 } END { for (i = NR; i >= 1; i--) print lines[i] }' "$log" >"$reversed"
  while IFS="$tab" read -r source destination; do
    [ -n "$source" ] || continue
    if [ -e "$destination" ] && [ ! -e "$source" ]; then
      mv "$destination" "$source" || wb_error "rollback failed: $destination -> $source"
    fi
  done <"$reversed"
}

validate_batch_entry() {
  repository=$1
  destination=$2
  workspace=$3
  original=$4
  quarantined=$5
  target=$6
  trunk_ref=$7
  trunk_revision=$8

  printf '%s\n' "$repository" | grep -Eq '^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$' || return 1
  printf '%s\n' "$destination" | grep -Eq '^[A-Za-z0-9][A-Za-z0-9._-]*$' || return 1
  printf '%s\n' "$workspace" | grep -Eq '^[A-Za-z0-9][A-Za-z0-9._-]*$' || return 1
  [ "$(dirname "$original")" = "$target_root" ] || return 1
  [ "$quarantined" = "$batch_dir/$repository/$(basename "$original")" ] || return 1
  [ -n "$target" ] && [ -n "$trunk_ref" ] && [ -n "$trunk_revision" ] || return 1
  wb_manifest_mapping_matches "$repository" "$destination" || return 1
  canonical=$target_root/$destination
  [ -d "$canonical" ] && [ ! -L "$canonical" ] || return 1
  wb_matching_remote "$canonical" "$repository" >/dev/null || return 1
  registered=$(registration_target "$canonical" "$workspace" 2>/dev/null || true)
  [ "$registered" = "$target" ] || return 1
  return 0
}

load_and_validate_batch() {
  wb_validate_batch_id "$batch_id" || wb_die "invalid batch ID: $batch_id"
  batch_dir=$quarantine_root/$batch_id
  manifest=$batch_dir/manifest.tsv
  [ -d "$batch_dir" ] && [ ! -L "$batch_dir" ] || wb_die "batch not found: $batch_id"
  [ -f "$manifest" ] && [ ! -L "$manifest" ] || wb_die "batch manifest missing: $manifest"

  batch_entries=$temporary_root/batch-entries.tsv
  awk -F '\t' '
    /^[[:space:]]*#/ || /^[[:space:]]*$/ { next }
    NF != 8 { exit 2 }
    { print }
  ' "$manifest" >"$batch_entries" || wb_die "invalid batch manifest: $manifest"
  [ -s "$batch_entries" ] || wb_die "batch manifest has no entries: $manifest"

  while IFS="$tab" read -r repository destination workspace original quarantined target trunk_ref trunk_revision; do
    validate_batch_entry "$repository" "$destination" "$workspace" "$original" "$quarantined" "$target" "$trunk_ref" "$trunk_revision" ||
      wb_die "batch entry no longer matches registered workspace: $workspace"
    [ -d "$quarantined" ] && [ ! -L "$quarantined" ] ||
      wb_die "quarantined workspace missing or unsafe: $quarantined"
    [ ! -e "$original" ] || wb_die "original workspace path is occupied: $original"
  done <"$batch_entries"
}

restore_batch() {
  load_and_validate_batch
  moved=$temporary_root/restored.tsv
  : >"$moved"

  while IFS="$tab" read -r repository destination workspace original quarantined target trunk_ref trunk_revision; do
    if ! $apply; then
      wb_info "would restore $workspace: $quarantined -> $original"
      continue
    fi
    if mv "$quarantined" "$original"; then
      printf '%s\t%s\n' "$quarantined" "$original" >>"$moved"
      wb_info "restored $workspace: $original"
    else
      wb_error "restore failed for $workspace; rolling back batch"
      rollback_moves "$moved"
      return 1
    fi
  done <"$batch_entries"

  if $apply; then
    rm -f "$manifest"
    remove_empty_batch_dirs "$batch_dir"
    wb_info "restored batch: $batch_id"
  else
    wb_info "preview only; rerun with --apply to restore batch $batch_id"
  fi
}

purge_batch() {
  load_and_validate_batch

  if ! $apply; then
    while IFS="$tab" read -r repository destination workspace original quarantined target trunk_ref trunk_revision; do
      wb_info "would permanently purge $workspace: $quarantined"
    done <"$batch_entries"
    wb_info "preview only; rerun with --apply to permanently purge batch $batch_id"
    return 0
  fi

  failures=0
  while IFS="$tab" read -r repository destination workspace original quarantined target trunk_ref trunk_revision; do
    canonical=$target_root/$destination
    if ! jj -R "$canonical" workspace forget "$workspace"; then
      wb_error "failed to forget workspace; preserved quarantine: $workspace"
      failures=$((failures + 1))
      continue
    fi
    if rm -rf "$quarantined"; then
      wb_info "purged $workspace"
    else
      wb_error "workspace forgotten but quarantine could not be deleted: $quarantined"
      failures=$((failures + 1))
    fi
  done <"$batch_entries"

  if [ "$failures" -eq 0 ]; then
    rm -f "$manifest"
    remove_empty_batch_dirs "$batch_dir"
    wb_info "purged batch: $batch_id"
  else
    wb_error "purge completed with $failures failure(s); batch manifest retained"
    return 1
  fi
}

case $operation in
  restore) restore_batch; exit $? ;;
  purge) purge_batch; exit $? ;;
esac

candidates=$temporary_root/candidates.tsv
: >"$candidates"
eligible=0
blocked=0
repositories_failed=0

block_workspace() {
  wb_info "blocked $1/$2: $3"
  blocked=$((blocked + 1))
}

selected=$temporary_root/selected.tsv
wb_manifest_rows "$profile" >"$selected"

while IFS="$tab" read -r repository destination _profiles trunk; do
  [ -n "$repository" ] || continue
  canonical=$target_root/$destination
  if [ ! -d "$canonical" ] || [ -L "$canonical" ]; then
    wb_error "$repository: canonical checkout missing or unsafe: $canonical"
    repositories_failed=$((repositories_failed + 1))
    continue
  fi
  remote=$(wb_matching_remote "$canonical" "$repository" 2>/dev/null || true)
  if [ -z "$remote" ]; then
    wb_error "$repository: no matching remote in canonical checkout"
    repositories_failed=$((repositories_failed + 1))
    continue
  fi
  trunk_ref=$trunk@$remote
  trunk_revision=$(jj -R "$canonical" --ignore-working-copy log -r "$trunk_ref" --no-graph \
    -T 'commit_id ++ "\n"' 2>/dev/null | sed -n '1p')
  if [ -z "$trunk_revision" ]; then
    wb_error "$repository: fetched trunk is unavailable: $trunk_ref"
    repositories_failed=$((repositories_failed + 1))
    continue
  fi

  rows=$temporary_root/workspaces.$$
  if ! workspace_rows "$canonical" >"$rows" 2>/dev/null; then
    wb_error "$repository: cannot list JJ workspaces"
    repositories_failed=$((repositories_failed + 1))
    continue
  fi

  while IFS="$tab" read -r workspace root target; do
    [ -n "$workspace" ] || continue
    if [ -z "$root" ]; then
      block_workspace "$repository" "$workspace" "stale or unresolved workspace root"
      continue
    fi
    if [ ! -d "$root" ] || [ -L "$root" ]; then
      block_workspace "$repository" "$workspace" "workspace root is missing or a symlink"
      continue
    fi
    resolved=$(wb_resolve_dir "$root" || true)
    if [ -z "$resolved" ] || [ "$(dirname "$resolved")" != "$target_root" ]; then
      block_workspace "$repository" "$workspace" "outside the direct sibling cleanup boundary"
      continue
    fi
    basename=$(basename "$resolved")
    if [ "$resolved" = "$canonical" ] || [ "$resolved" = "$WB_REPO_ROOT" ] ||
      [ "$basename" = ".workspace-quarantine" ] || wb_is_manifest_destination "$basename"; then
      continue
    fi
    printf '%s\n' "$workspace" | grep -Eq '^[A-Za-z0-9][A-Za-z0-9._-]*$' || {
      block_workspace "$repository" "$workspace" "workspace name is unsafe for quarantine"
      continue
    }
    dirty=$temporary_root/dirty.$$
    if ! jj -R "$resolved" --no-integrate-operation diff --summary >"$dirty" 2>/dev/null; then
      block_workspace "$repository" "$workspace" "cannot inspect live working copy"
      continue
    fi
    if [ -s "$dirty" ]; then
      block_workspace "$repository" "$workspace" "tracked or untracked working-copy changes"
      continue
    fi
    conflict=$(jj -R "$canonical" --ignore-working-copy log -r "$target" --no-graph \
      -T 'if(conflict, "1", "0") ++ "\n"' 2>/dev/null | sed -n '1p')
    if [ "$conflict" != 0 ]; then
      block_workspace "$repository" "$workspace" "conflicted or unreadable workspace target"
      continue
    fi
    unique_nonempty=$(jj -R "$canonical" --ignore-working-copy log \
      -r "(::$target ~ ::$trunk_ref) & ~root() & ~empty()" --no-graph \
      -T 'commit_id ++ "\n"' 2>/dev/null || printf 'query-failed\n')
    if [ -n "$unique_nonempty" ]; then
      block_workspace "$repository" "$workspace" "contains commits not integrated by exact ancestry"
      continue
    fi
    protecting_bookmarks=$(jj -R "$canonical" --ignore-working-copy log \
      -r "(::$target ~ ::$trunk_ref) & bookmarks()" --no-graph \
      -T 'local_bookmarks ++ "\n"' 2>/dev/null || printf 'query-failed\n')
    if [ -n "$protecting_bookmarks" ]; then
      block_workspace "$repository" "$workspace" "workspace-only commit has a local bookmark"
      continue
    fi

    printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
      "$repository" "$destination" "$workspace" "$resolved" "$target" "$trunk_ref" "$trunk_revision" >>"$candidates"
    wb_info "eligible $repository/$workspace: $resolved"
    eligible=$((eligible + 1))
  done <"$rows"
done <"$selected"

printf 'summary: eligible=%d blocked=%d repository_failures=%d\n' \
  "$eligible" "$blocked" "$repositories_failed"

if ! $apply; then
  wb_info "preview only; rerun with --apply to quarantine eligible workspaces"
  [ "$repositories_failed" -eq 0 ]
  exit $?
fi

[ "$repositories_failed" -eq 0 ] || wb_die "refusing quarantine while canonical repositories failed validation"
[ "$eligible" -gt 0 ] || { wb_info "no eligible workspaces to quarantine"; exit 0; }

batch_id=$(date -u '+%Y%m%dT%H%M%SZ')-$$
batch_dir=$quarantine_root/$batch_id
manifest=$batch_dir/manifest.tsv
moved=$temporary_root/quarantined.tsv
: >"$moved"

while IFS="$tab" read -r repository destination workspace original target trunk_ref trunk_revision; do
  quarantined=$batch_dir/$repository/$(basename "$original")
  [ ! -e "$quarantined" ] || wb_die "quarantine destination already exists: $quarantined"
done <"$candidates"

mkdir -p "$batch_dir" || wb_die "cannot create quarantine batch: $batch_dir"
printf '# repository\tdestination\tworkspace\toriginal\tquarantined\ttarget\ttrunk-ref\ttrunk-revision\n' >"$manifest" ||
  wb_die "cannot create batch manifest"

while IFS="$tab" read -r repository destination workspace original target trunk_ref trunk_revision; do
  quarantined=$batch_dir/$repository/$(basename "$original")
  mkdir -p "$(dirname "$quarantined")" || {
    wb_error "cannot create quarantine destination; rolling back batch"
    rollback_moves "$moved"
    rm -f "$manifest"
    remove_empty_batch_dirs "$batch_dir"
    exit 1
  }
  if ! mv "$original" "$quarantined"; then
    wb_error "cannot quarantine $workspace; rolling back batch"
    rollback_moves "$moved"
    rm -f "$manifest"
    remove_empty_batch_dirs "$batch_dir"
    exit 1
  fi
  printf '%s\t%s\n' "$original" "$quarantined" >>"$moved"
  printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
    "$repository" "$destination" "$workspace" "$original" "$quarantined" "$target" "$trunk_ref" "$trunk_revision" >>"$manifest"
  wb_info "quarantined $repository/$workspace: $quarantined"
done <"$candidates"

wb_info "quarantine batch: $batch_id"
wb_info "restore with: ./cleanup-workspaces.sh --restore $batch_id --apply"
wb_info "purge with: ./cleanup-workspaces.sh --purge $batch_id --apply"
