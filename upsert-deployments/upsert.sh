#!/usr/bin/env bash
# List github-pages (or --environment) deployments and prune per --mode.
# Soft-fail: API/per-id errors are logged; exit 0 unless bad args.
# Usage:
#   upsert.sh --owner O --repo R --ref REF --mode replace|purge [--environment github-pages]
# Requires: gh, jq, GH_TOKEN (or gh auth)
set -euo pipefail

owner=""
repo=""
ref=""
mode=""
environment="github-pages"

usage() {
  echo "Usage: $0 --owner O --repo R --ref REF --mode replace|purge [--environment ENV]" >&2
  exit 2
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --owner) owner="${2:-}"; shift 2 ;;
    --repo) repo="${2:-}"; shift 2 ;;
    --ref) ref="${2:-}"; shift 2 ;;
    --mode) mode="${2:-}"; shift 2 ;;
    --environment) environment="${2:-}"; shift 2 ;;
    -h|--help) usage ;;
    *) echo "unknown arg: $1" >&2; usage ;;
  esac
done

[[ -n "$owner" && -n "$repo" && -n "$ref" && -n "$mode" ]] || usage
[[ "$mode" == "replace" || "$mode" == "purge" ]] || usage

script_dir="$(cd "$(dirname "$0")" && pwd -P)"

tmpdir="$(mktemp -d "${TMPDIR:-/tmp}/upsert-deployments.XXXXXX")"
trap 'rm -rf "$tmpdir"' EXIT
list_file="$tmpdir/list.json"

set +e
gh api --paginate \
  "repos/${owner}/${repo}/deployments?environment=${environment}&per_page=100" \
  >"$list_file" 2>"$tmpdir/list.err"
list_rc=$?
set -e

if [[ "$list_rc" -ne 0 ]]; then
  echo "warning: failed to list deployments (exit $list_rc); skipping upsert" >&2
  cat "$tmpdir/list.err" >&2 || true
  exit 0
fi

# --paginate may concatenate JSON arrays; normalize to one array
if ! jq -s 'add // []' "$list_file" >"$tmpdir/all.json" 2>/dev/null; then
  # single array page
  cp "$list_file" "$tmpdir/all.json"
fi

ids="$("$script_dir/select_ids.sh" --ref "$ref" --mode "$mode" <"$tmpdir/all.json" || true)"
if [[ -z "${ids}" ]]; then
  echo "upsert-deployments: nothing to delete for ref=$ref mode=$mode"
  exit 0
fi

while IFS= read -r id; do
  [[ -n "$id" ]] || continue
  echo "upsert-deployments: deleting deployment $id (ref=$ref mode=$mode)"
  set +e
  gh api -X POST "repos/${owner}/${repo}/deployments/${id}/statuses" \
    -f state=inactive \
    -f description="upsert-deployments ${mode}" >/dev/null 2>"$tmpdir/status.err"
  gh api -X DELETE "repos/${owner}/${repo}/deployments/${id}" \
    >/dev/null 2>"$tmpdir/del.err"
  del_rc=$?
  set -e
  if [[ "$del_rc" -ne 0 ]]; then
    echo "warning: failed to delete deployment $id" >&2
    cat "$tmpdir/del.err" >&2 || true
  fi
done <<<"$ids"

exit 0
