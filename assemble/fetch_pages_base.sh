#!/usr/bin/env bash
# Download the latest successful github-pages Actions artifact into --out.
#
# Usage:
#   fetch_pages_base.sh --repo owner/name --out DIR
#                       [--name github-pages] [--exclude-run-id ID]
#                       [--token TOKEN]
#
# Exit 0 with files in --out when found.
# Exit 3 when no eligible artifact (caller should full-rebuild).
# Other non-zero: hard failure.
set -euo pipefail

repo=""
out=""
name="github-pages"
exclude_run_id=""
token="${GH_TOKEN:-${GITHUB_TOKEN:-}}"

usage() {
  echo "Usage: $0 --repo owner/name --out DIR [--name NAME] [--exclude-run-id ID]" >&2
  exit 2
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --repo) repo="${2:-}"; shift 2 ;;
    --out) out="${2:-}"; shift 2 ;;
    --name) name="${2:-}"; shift 2 ;;
    --exclude-run-id) exclude_run_id="${2:-}"; shift 2 ;;
    --token) token="${2:-}"; shift 2 ;;
    -h|--help) usage ;;
    *) echo "unknown arg: $1" >&2; usage ;;
  esac
done

[[ -n "$repo" && -n "$out" ]] || usage
command -v gh >/dev/null 2>&1 || {
  echo "error: gh not found" >&2
  exit 1
}
command -v jq >/dev/null 2>&1 || {
  echo "error: jq not found" >&2
  exit 1
}

script_dir="$(cd "$(dirname "$0")" && pwd -P)"
select_sh="$script_dir/select_pages_artifact.sh"
[[ -f "$select_sh" ]] || {
  echo "error: select_pages_artifact.sh missing next to fetch_pages_base.sh" >&2
  exit 1
}
chmod +x "$select_sh" 2>/dev/null || true

export GH_TOKEN="${token}"

# Paginate artifacts; soft-cap pages to keep CI bounded.
artifacts_json='[]'
page=1
while [[ "$page" -le 5 ]]; do
  chunk="$(gh api "repos/${repo}/actions/artifacts?per_page=100&page=${page}" --jq '.artifacts')"
  count="$(jq 'length' <<<"$chunk")"
  artifacts_json="$(jq -c --argjson a "$artifacts_json" --argjson b "$chunk" '$a + $b')"
  [[ "$count" -lt 100 ]] && break
  page=$((page + 1))
done

select_args=(--name "$name")
if [[ -n "$exclude_run_id" ]]; then
  select_args+=(--exclude-run-id "$exclude_run_id")
fi
artifact_id="$(printf '%s' "$artifacts_json" | "$select_sh" "${select_args[@]}")"
if [[ -z "$artifact_id" ]]; then
  echo "warning: no eligible ${name} artifact for ${repo}; no base" >&2
  mkdir -p "$out"
  exit 3
fi

tmp="$(mktemp -d "${TMPDIR:-/tmp}/api-docs-pages-base.XXXXXX")"
cleanup() { rm -rf "$tmp"; }
trap cleanup EXIT

zip_path="$tmp/pages.zip"
gh api "repos/${repo}/actions/artifacts/${artifact_id}/zip" >"$zip_path"
mkdir -p "$tmp/extract"
unzip -q "$zip_path" -d "$tmp/extract"

rm -rf "$out"
mkdir -p "$out"
shopt -s dotglob nullglob
if [[ -n "$(find "$tmp/extract" -mindepth 1 -maxdepth 1 2>/dev/null | head -n1)" ]]; then
  cp -a "$tmp/extract"/* "$out"/
fi
shopt -u dotglob nullglob

echo "fetched pages base from artifact ${artifact_id} into $out"
