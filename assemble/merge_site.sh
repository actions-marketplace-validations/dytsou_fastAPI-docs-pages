#!/usr/bin/env bash
# Merge path-scoped deltas into a GitHub Pages site tree.
#
# Usage:
#   merge_site.sh --base DIR --out DIR --overlay DIR
#   merge_site.sh --base DIR --out DIR --remove-pr N
#   merge_site.sh --base DIR --out DIR --overlay DIR --remove-pr N
#
# --overlay: copy overlay contents into out (after cloning base). Main docs and
#   pr-preview/pr-<n>/ trees in the overlay replace matching paths; siblings stay.
# --remove-pr: delete pr-preview/pr-<n>/ from the result.
# Empty/missing base: out starts empty, then overlay/remove apply.
# Safe when --base and --out are the same path (stages via a temp dir).
set -euo pipefail

base=""
out=""
overlay=""
remove_pr=""

usage() {
  echo "Usage: $0 --base DIR --out DIR [--overlay DIR] [--remove-pr N]" >&2
  exit 2
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --base) base="${2:-}"; shift 2 ;;
    --out) out="${2:-}"; shift 2 ;;
    --overlay) overlay="${2:-}"; shift 2 ;;
    --remove-pr) remove_pr="${2:-}"; shift 2 ;;
    -h|--help) usage ;;
    *) echo "unknown arg: $1" >&2; usage ;;
  esac
done

[[ -n "$base" && -n "$out" ]] || usage
[[ -n "$overlay" || -n "$remove_pr" ]] || usage

stage="$(mktemp -d "${TMPDIR:-/tmp}/api-docs-merge.XXXXXX")"
cleanup() { rm -rf "$stage"; }
trap cleanup EXIT

dir_nonempty() {
  local d="$1"
  [[ -d "$d" ]] || return 1
  [[ -n "$(find "$d" -mindepth 1 -maxdepth 1 2>/dev/null | head -n1)" ]]
}

if dir_nonempty "$base"; then
  shopt -s dotglob nullglob
  cp -a "$base"/* "$stage"/
  shopt -u dotglob nullglob
fi

if [[ -n "$overlay" ]]; then
  [[ -d "$overlay" ]] || {
    echo "error: overlay is not a directory: $overlay" >&2
    exit 1
  }
  shopt -s dotglob nullglob
  for entry in "$overlay"/*; do
    name="$(basename "$entry")"
    if [[ "$name" == "pr-preview" && -d "$entry" ]]; then
      mkdir -p "$stage/pr-preview"
      for pr_dir in "$entry"/*; do
        [[ -e "$pr_dir" ]] || continue
        pr_name="$(basename "$pr_dir")"
        rm -rf "$stage/pr-preview/$pr_name"
        cp -a "$pr_dir" "$stage/pr-preview/$pr_name"
      done
    else
      rm -rf "$stage/$name"
      cp -a "$entry" "$stage/$name"
    fi
  done
  shopt -u dotglob nullglob
fi

if [[ -n "$remove_pr" ]]; then
  rm -rf "$stage/pr-preview/pr-${remove_pr}"
  if [[ -d "$stage/pr-preview" ]] && ! dir_nonempty "$stage/pr-preview"; then
    rmdir "$stage/pr-preview" 2>/dev/null || true
  fi
fi

out_parent="$(dirname "$out")"
mkdir -p "$out_parent"
rm -rf "$out"
mkdir -p "$out"
if dir_nonempty "$stage"; then
  shopt -s dotglob nullglob
  cp -a "$stage"/* "$out"/
  shopt -u dotglob nullglob
fi

echo "merged site at $out"
