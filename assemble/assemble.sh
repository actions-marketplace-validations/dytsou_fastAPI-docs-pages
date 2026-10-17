#!/usr/bin/env bash
# Assemble GitHub Pages site: main /docs/ + open same-repo PR previews.
# For each git ref, runs export-command (must write openapi-path), then build-site.
#
# Env set for export-command:
#   API_DOCS_TREE_ROOT   — absolute path to the worktree for this ref
#   API_DOCS_WORKSPACE   — primary checkout (usually GITHUB_WORKSPACE)
#
# Usage:
#   assemble.sh --out DIR --repo owner/name --export-command CMD
#               [--openapi-path PATH] [--working-directory DIR]
#               [--default-ref REF] [--omit-pr N] [--title TITLE]
#               [--renderer swagger|redocly|both]
set -euo pipefail

out=""
default_ref="origin/main"
omit_pr=""
repo="${GITHUB_REPOSITORY:-}"
export_command=""
openapi_path="openapi.json"
working_directory="."
title="API docs"
renderer="swagger"

usage() {
  echo "Usage: $0 --out DIR --repo owner/name --export-command CMD [options]" >&2
  exit 2
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --out) out="${2:-}"; shift 2 ;;
    --default-ref) default_ref="${2:-}"; shift 2 ;;
    --omit-pr) omit_pr="${2:-}"; shift 2 ;;
    --repo) repo="${2:-}"; shift 2 ;;
    --export-command) export_command="${2:-}"; shift 2 ;;
    --openapi-path) openapi_path="${2:-}"; shift 2 ;;
    --working-directory) working_directory="${2:-}"; shift 2 ;;
    --title) title="${2:-}"; shift 2 ;;
    --renderer) renderer="${2:-}"; shift 2 ;;
    -h|--help) usage ;;
    *) echo "unknown arg: $1" >&2; usage ;;
  esac
done

[[ -n "$out" && -n "$repo" && -n "$export_command" ]] || usage

script_dir="$(cd "$(dirname "$0")" && pwd -P)"
build_sh="$(cd "$script_dir/../build-site" && pwd -P)/build.sh"
[[ -x "$build_sh" || -f "$build_sh" ]] || {
  echo "error: build-site/build.sh not found next to assemble/" >&2
  exit 1
}
chmod +x "$build_sh" 2>/dev/null || true

root="$(git rev-parse --show-toplevel)"
workspace="${API_DOCS_WORKSPACE:-${GITHUB_WORKSPACE:-$root}}"
out="$(mkdir -p "$out" && cd "$out" && pwd -P)"

if [[ -d "$out" ]]; then
  find "$out" -mindepth 1 -maxdepth 1 -exec rm -rf {} +
fi

build_from_tree() {
  local tree="$1"
  local site_out="$2"
  local openapi_abs="$tree/$openapi_path"

  mkdir -p "$(dirname "$openapi_abs")"
  (
    export API_DOCS_TREE_ROOT="$tree"
    export API_DOCS_WORKSPACE="$workspace"
    cd "$tree/$working_directory"
    bash -euo pipefail -c "$export_command"
  )
  if [[ ! -f "$openapi_abs" ]]; then
    echo "error: export-command did not write $openapi_abs" >&2
    return 1
  fi
  "$build_sh" --openapi "$openapi_abs" --out "$site_out" --title "$title" --renderer "$renderer"
}

echo "Building main site from $default_ref ..."
main_tmp="$(mktemp -d "${TMPDIR:-/tmp}/api-docs-main.XXXXXX")"
cleanup_main() { git -C "$root" worktree remove --force "$main_tmp" 2>/dev/null || rm -rf "$main_tmp"; }
trap cleanup_main EXIT
git -C "$root" worktree add --force --detach "$main_tmp" "$default_ref"
build_from_tree "$main_tmp" "$out"
cleanup_main
trap - EXIT

if ! command -v gh >/dev/null 2>&1; then
  echo "warning: gh not found; skipping PR previews" >&2
  echo "assembled site at $out"
  exit 0
fi

echo "Listing open same-repo PRs for $repo ..."
mapfile -t pr_rows < <(
  gh pr list --repo "$repo" --state open --limit 100 \
    --json number,headRefOid,isCrossRepository \
    --jq '.[] | select(.isCrossRepository | not) | "\(.number)\t\(.headRefOid)"'
)

for row in "${pr_rows[@]+"${pr_rows[@]}"}"; do
  [[ -n "$row" ]] || continue
  number="${row%%$'\t'*}"
  oid="${row#*$'\t'}"
  if [[ -n "$omit_pr" && "$number" == "$omit_pr" ]]; then
    echo "Omitting closed PR #$number"
    continue
  fi
  echo "Building preview for PR #$number ($oid) ..."
  pr_tmp="$(mktemp -d "${TMPDIR:-/tmp}/api-docs-pr-${number}.XXXXXX")"
  cleanup_pr() { git -C "$root" worktree remove --force "$pr_tmp" 2>/dev/null || rm -rf "$pr_tmp"; }
  trap cleanup_pr EXIT
  if ! git -C "$root" fetch --depth 1 origin "$oid"; then
    echo "warning: fetch failed for PR #$number" >&2
    cleanup_pr
    trap - EXIT
    continue
  fi
  git -C "$root" worktree add --force --detach "$pr_tmp" "$oid"
  pr_out="$out/pr-preview/pr-${number}"
  if ! build_from_tree "$pr_tmp" "$pr_out"; then
    echo "warning: build failed for PR #$number" >&2
    rm -rf "$pr_out"
  fi
  cleanup_pr
  trap - EXIT
done

echo "assembled site at $out"
