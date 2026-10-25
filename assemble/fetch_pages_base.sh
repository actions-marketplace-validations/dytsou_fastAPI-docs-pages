#!/usr/bin/env bash
# Download the latest successful github-pages Actions artifact into --out.
#
# Usage:
#   fetch_pages_base.sh --repo owner/name --out DIR
#                       [--name github-pages] [--exclude-run-id ID]
#                       [--token TOKEN]
#   fetch_pages_base.sh --from-zip ZIP --out DIR   # test / offline unpack
#
# Exit 0 with a usable site tree in --out.
# Exit 3 when no eligible artifact or unpack does not yield a site tree
#   (caller should full-rebuild).
# Other non-zero: hard failure.
#
# GitHub's upload-pages-artifact stores a zip whose payload is artifact.tar
# (not an exploded HTML tree). We unzip, then tar -xf when needed.
set -euo pipefail

repo=""
out=""
name="github-pages"
exclude_run_id=""
token="${GH_TOKEN:-${GITHUB_TOKEN:-}}"
from_zip=""

usage() {
  echo "Usage: $0 --out DIR (--repo owner/name | --from-zip ZIP) [options]" >&2
  exit 2
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --repo) repo="${2:-}"; shift 2 ;;
    --out) out="${2:-}"; shift 2 ;;
    --name) name="${2:-}"; shift 2 ;;
    --exclude-run-id) exclude_run_id="${2:-}"; shift 2 ;;
    --token) token="${2:-}"; shift 2 ;;
    --from-zip) from_zip="${2:-}"; shift 2 ;;
    -h|--help) usage ;;
    *) echo "unknown arg: $1" >&2; usage ;;
  esac
done

[[ -n "$out" ]] || usage
if [[ -z "$from_zip" && -z "$repo" ]]; then
  usage
fi

dir_nonempty() {
  local d="$1"
  [[ -d "$d" ]] || return 1
  [[ -n "$(find "$d" -mindepth 1 -maxdepth 1 2>/dev/null | head -n1)" ]]
}

# Plausible Pages site: main docs, root redirect, or a PR preview tree.
is_site_tree() {
  local d="$1"
  [[ -d "$d/docs" || -f "$d/index.html" || -d "$d/pr-preview" || -d "$d/redoc" ]]
}

# Unpack upload-pages-artifact zip (artifact.tar inside) or a plain site zip.
materialize_from_zip() {
  local zip_path="$1"
  local dest="$2"
  local tmp extract
  tmp="$(mktemp -d "${TMPDIR:-/tmp}/api-docs-pages-unpack.XXXXXX")"
  extract="$tmp/extract"
  mkdir -p "$extract"
  unzip -q "$zip_path" -d "$extract"

  rm -rf "$dest"
  mkdir -p "$dest"

  if [[ -f "$extract/artifact.tar" ]]; then
    tar -xf "$extract/artifact.tar" -C "$dest"
  elif dir_nonempty "$extract"; then
    shopt -s dotglob nullglob
    cp -a "$extract"/* "$dest"/
    shopt -u dotglob nullglob
  fi
  rm -rf "$tmp"

  if ! is_site_tree "$dest"; then
    echo "warning: unpacked artifact is not a usable Pages site tree" >&2
    rm -rf "$dest"
    mkdir -p "$dest"
    return 3
  fi
  return 0
}

if [[ -n "$from_zip" ]]; then
  [[ -f "$from_zip" ]] || {
    echo "error: --from-zip not a file: $from_zip" >&2
    exit 1
  }
  set +e
  materialize_from_zip "$from_zip" "$out"
  rc=$?
  set -e
  if [[ "$rc" -eq 3 ]]; then
    exit 3
  elif [[ "$rc" -ne 0 ]]; then
    exit "$rc"
  fi
  echo "fetched pages base from zip into $out"
  exit 0
fi

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

set +e
materialize_from_zip "$zip_path" "$out"
rc=$?
set -e
if [[ "$rc" -eq 3 ]]; then
  exit 3
elif [[ "$rc" -ne 0 ]]; then
  exit "$rc"
fi

echo "fetched pages base from artifact ${artifact_id} into $out"
