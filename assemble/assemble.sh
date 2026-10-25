#!/usr/bin/env bash
# Assemble GitHub Pages site deltas or a full main + PR preview tree.
# For each git ref, runs export-command (must write openapi-path), then build-site.
#
# Env set for export-command:
#   API_DOCS_TREE_ROOT   — absolute path to the worktree for this ref
#   API_DOCS_WORKSPACE   — primary checkout (usually GITHUB_WORKSPACE)
#
# Usage:
#   assemble.sh --out DIR --repo owner/name --export-command CMD
#               [--mode full|main|pr] [--pr N] [--pr-oid OID]
#               [--openapi-path PATH] [--working-directory DIR]
#               [--default-ref REF] [--omit-pr N] [--require-pr N]
#               [--title TITLE] [--renderer swagger|redocly|both]
#
# Modes:
#   full — main + all open same-repo PR previews (default; omit-pr supported)
#   main — default-ref only into out root
#   pr   — single PR preview under pr-preview/pr-<n>/ (needs --pr; oid via
#          --pr-oid or gh)
set -euo pipefail

out=""
default_ref="origin/main"
omit_pr=""
require_pr=""
repo="${GITHUB_REPOSITORY:-}"
export_command=""
openapi_path="openapi.json"
working_directory="."
title="API docs"
renderer="swagger"
mode="full"
pr_number=""
pr_oid=""

usage() {
  echo "Usage: $0 --out DIR --repo owner/name --export-command CMD [options]" >&2
  exit 2
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --out) out="${2:-}"; shift 2 ;;
    --default-ref) default_ref="${2:-}"; shift 2 ;;
    --omit-pr) omit_pr="${2:-}"; shift 2 ;;
    --require-pr) require_pr="${2:-}"; shift 2 ;;
    --repo) repo="${2:-}"; shift 2 ;;
    --export-command) export_command="${2:-}"; shift 2 ;;
    --openapi-path) openapi_path="${2:-}"; shift 2 ;;
    --working-directory) working_directory="${2:-}"; shift 2 ;;
    --title) title="${2:-}"; shift 2 ;;
    --renderer) renderer="${2:-}"; shift 2 ;;
    --mode) mode="${2:-}"; shift 2 ;;
    --pr) pr_number="${2:-}"; shift 2 ;;
    --pr-oid) pr_oid="${2:-}"; shift 2 ;;
    -h|--help) usage ;;
    *) echo "unknown arg: $1" >&2; usage ;;
  esac
done

[[ -n "$out" && -n "$repo" && -n "$export_command" ]] || usage
case "$mode" in
  full|main|pr) ;;
  *) echo "error: --mode must be full, main, or pr (got: $mode)" >&2; exit 2 ;;
esac
if [[ "$mode" == "pr" && -z "$pr_number" ]]; then
  echo "error: --mode pr requires --pr N" >&2
  exit 2
fi

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

build_main() {
  echo "Building main site from $default_ref ..."
  local main_tmp
  main_tmp="$(mktemp -d "${TMPDIR:-/tmp}/api-docs-main.XXXXXX")"
  cleanup_main() { git -C "$root" worktree remove --force "$main_tmp" 2>/dev/null || rm -rf "$main_tmp"; }
  trap cleanup_main EXIT
  git -C "$root" worktree add --force --detach "$main_tmp" "$default_ref"
  build_from_tree "$main_tmp" "$out"
  cleanup_main
  trap - EXIT
}

build_one_pr() {
  local number="$1"
  local oid="$2"
  local required="${3:-}"

  echo "Building preview for PR #$number ($oid) ..."
  local pr_tmp
  pr_tmp="$(mktemp -d "${TMPDIR:-/tmp}/api-docs-pr-${number}.XXXXXX")"
  cleanup_pr() { git -C "$root" worktree remove --force "$pr_tmp" 2>/dev/null || rm -rf "$pr_tmp"; }
  trap cleanup_pr EXIT
  if ! git -C "$root" fetch --depth 1 origin "$oid"; then
    echo "warning: fetch failed for PR #$number" >&2
    cleanup_pr
    trap - EXIT
    if [[ -n "$required" && "$number" == "$required" ]]; then
      echo "error: required PR #$required fetch failed" >&2
      exit 1
    fi
    return 1
  fi
  git -C "$root" worktree add --force --detach "$pr_tmp" "$oid"
  local pr_out="$out/pr-preview/pr-${number}"
  if ! build_from_tree "$pr_tmp" "$pr_out"; then
    echo "warning: build failed for PR #$number" >&2
    rm -rf "$pr_out"
    cleanup_pr
    trap - EXIT
    if [[ -n "$required" && "$number" == "$required" ]]; then
      echo "error: required PR #$required preview build failed" >&2
      exit 1
    fi
    return 1
  fi
  cleanup_pr
  trap - EXIT
  return 0
}

resolve_pr_oid() {
  local number="$1"
  if [[ -n "$pr_oid" ]]; then
    printf '%s' "$pr_oid"
    return 0
  fi
  if ! command -v gh >/dev/null 2>&1; then
    echo "error: gh not found; pass --pr-oid for PR #$number" >&2
    exit 1
  fi
  gh pr view "$number" --repo "$repo" --json headRefOid,isCrossRepository \
    --jq 'if .isCrossRepository then empty else .headRefOid end'
}

case "$mode" in
  main)
    build_main
    ;;
  pr)
    oid="$(resolve_pr_oid "$pr_number")"
    if [[ -z "$oid" ]]; then
      echo "error: cannot resolve head oid for PR #$pr_number (missing or cross-repo)" >&2
      exit 1
    fi
    req="${require_pr:-$pr_number}"
    build_one_pr "$pr_number" "$oid" "$req"
    if [[ ! -d "$out/pr-preview/pr-${pr_number}" ]]; then
      echo "error: required PR #$pr_number preview missing under $out/pr-preview/" >&2
      exit 1
    fi
    ;;
  full)
    build_main

    if ! command -v gh >/dev/null 2>&1; then
      if [[ -n "$require_pr" ]]; then
        echo "error: gh not found; cannot build required PR #$require_pr preview" >&2
        exit 1
      fi
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
      build_one_pr "$number" "$oid" "$require_pr" || true
    done

    if [[ -n "$require_pr" && ! -d "$out/pr-preview/pr-${require_pr}" ]]; then
      echo "error: required PR #$require_pr preview missing under $out/pr-preview/" >&2
      exit 1
    fi
    ;;
esac

echo "assembled site at $out"
