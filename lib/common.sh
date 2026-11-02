#!/bin/sh
# SPDX-License-Identifier: Apache-2.0

wb_error() {
  printf 'error: %s\n' "$*" >&2
}

wb_info() {
  printf '%s\n' "$*"
}

wb_die() {
  wb_error "$*"
  exit 1
}

wb_require_command() {
  command -v "$1" >/dev/null 2>&1 || wb_die "required command not found: $1"
}

wb_resolve_dir() {
  (CDPATH='' cd "$1" 2>/dev/null && pwd -P)
}

wb_require_repo_root() {
  actual=$(pwd -P) || wb_die "cannot resolve current directory"
  [ "$actual" = "$WB_REPO_ROOT" ] ||
    wb_die "run this command from $WB_REPO_ROOT"
}

wb_validate_profile() {
  case $1 in
    active | all) ;;
    *) wb_die "profile must be active or all: $1" ;;
  esac
}

wb_validate_manifest() {
  [ -f "$WB_MANIFEST" ] || wb_die "manifest not found: $WB_MANIFEST"

  awk -F '\t' '
    BEGIN { active = 0; total = 0; errors = 0 }
    /^[[:space:]]*#/ || /^[[:space:]]*$/ { next }
    {
      total++
      if (NF != 4) {
        printf "manifest line %d: expected 4 tab-separated fields\n", NR > "/dev/stderr"
        errors++
        next
      }
      if ($1 !~ /^[A-Za-z0-9_.-]+\/[A-Za-z0-9_.-]+$/) {
        printf "manifest line %d: invalid repository: %s\n", NR, $1 > "/dev/stderr"
        errors++
      }
      if ($2 !~ /^[A-Za-z0-9][A-Za-z0-9._-]*$/ || $2 == "." || $2 == "..") {
        printf "manifest line %d: unsafe destination: %s\n", NR, $2 > "/dev/stderr"
        errors++
      }
      if ($3 != "active,all" && $3 != "all") {
        printf "manifest line %d: invalid profiles: %s\n", NR, $3 > "/dev/stderr"
        errors++
      }
      if ($4 !~ /^[A-Za-z0-9][A-Za-z0-9._\/-]*$/) {
        printf "manifest line %d: invalid trunk: %s\n", NR, $4 > "/dev/stderr"
        errors++
      }
      if (repositories[$1]++) {
        printf "manifest line %d: duplicate repository: %s\n", NR, $1 > "/dev/stderr"
        errors++
      }
      if (destinations[$2]++) {
        printf "manifest line %d: duplicate destination: %s\n", NR, $2 > "/dev/stderr"
        errors++
      }
      if ($3 == "active,all") active++
    }
    END {
      expected_active = ENVIRON["WB_EXPECT_ACTIVE"] + 0
      expected_all = ENVIRON["WB_EXPECT_ALL"] + 0
      if (expected_active == 0) expected_active = 22
      if (expected_all == 0) expected_all = 30
      if (active != expected_active) {
        printf "manifest: expected %d active entries, found %d\n", expected_active, active > "/dev/stderr"
        errors++
      }
      if (total != expected_all) {
        printf "manifest: expected %d total entries, found %d\n", expected_all, total > "/dev/stderr"
        errors++
      }
      exit(errors != 0)
    }
  ' "$WB_MANIFEST" || wb_die "manifest validation failed"
}

wb_manifest_rows() {
  profile=$1
  awk -F '\t' -v profile="$profile" '
    /^[[:space:]]*#/ || /^[[:space:]]*$/ { next }
    profile == "all" || $3 == "active,all" { print }
  ' "$WB_MANIFEST"
}

wb_normalize_github_url() {
  printf '%s\n' "$1" |
    sed -E \
      -e 's#^git@github\.com:##' \
      -e 's#^ssh://git@github\.com/##' \
      -e 's#^https?://github\.com/##' \
      -e 's#^git://github\.com/##' \
      -e 's#/$##' \
      -e 's#\.git$##' |
    tr '[:upper:]' '[:lower:]'
}

wb_matching_remote() {
  checkout=$1
  expected=$(printf '%s' "$2" | tr '[:upper:]' '[:lower:]')

  git -C "$checkout" rev-parse --git-dir >/dev/null 2>&1 || return 1
  for remote in $(git -C "$checkout" remote 2>/dev/null); do
    url=$(git -C "$checkout" remote get-url "$remote" 2>/dev/null || true)
    [ -n "$url" ] || continue
    normalized=$(wb_normalize_github_url "$url")
    if [ "$normalized" = "$expected" ]; then
      printf '%s\n' "$remote"
      return 0
    fi
  done
  return 1
}

wb_is_manifest_destination() {
  candidate=$1
  awk -F '\t' -v candidate="$candidate" '
    /^[[:space:]]*#/ || /^[[:space:]]*$/ { next }
    $2 == candidate { found = 1 }
    END { exit(!found) }
  ' "$WB_MANIFEST"
}

wb_manifest_mapping_matches() {
  repository=$1
  destination=$2
  awk -F '\t' -v repository="$repository" -v destination="$destination" '
    /^[[:space:]]*#/ || /^[[:space:]]*$/ { next }
    $1 == repository && $2 == destination { found = 1 }
    END { exit(!found) }
  ' "$WB_MANIFEST"
}

wb_validate_batch_id() {
  printf '%s\n' "$1" | grep -Eq '^[0-9]{8}T[0-9]{6}Z-[0-9]+$'
}
