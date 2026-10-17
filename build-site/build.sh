#!/usr/bin/env bash
# Build a static API docs site from an OpenAPI document.
# Usage:
#   build.sh --openapi FILE --out DIR [--title TITLE] [--renderer swagger|redocly|both]
set -euo pipefail

# Pin versions; bump intentionally when upgrading.
SWAGGER_UI_VERSION="${SWAGGER_UI_VERSION:-5.33.3}"
REDOCLY_CLI_VERSION="${REDOCLY_CLI_VERSION:-2.64.1}"
CDN_BASE="https://cdn.jsdelivr.net/npm/swagger-ui-dist@${SWAGGER_UI_VERSION}"

openapi=""
out=""
title="API docs"
renderer="swagger"

usage() {
  echo "Usage: $0 --openapi FILE --out DIR [--title TITLE] [--renderer swagger|redocly|both]" >&2
  exit 2
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --openapi) openapi="${2:-}"; shift 2 ;;
    --out) out="${2:-}"; shift 2 ;;
    --title) title="${2:-}"; shift 2 ;;
    --renderer) renderer="${2:-}"; shift 2 ;;
    -h|--help) usage ;;
    *) echo "unknown arg: $1" >&2; usage ;;
  esac
done

[[ -n "$openapi" && -n "$out" && -f "$openapi" ]] || usage
case "$renderer" in
  swagger|redocly|both) ;;
  *) echo "error: --renderer must be swagger, redocly, or both (got: $renderer)" >&2; exit 2 ;;
esac

out="$(mkdir -p "$out" && cd "$out" && pwd -P)"
openapi_abs="$(cd "$(dirname "$openapi")" && pwd -P)/$(basename "$openapi")"

write_root_files() {
  : >"$out/.nojekyll"
  cat >"$out/index.html" <<'EOF'
<!DOCTYPE html><meta http-equiv="refresh" content="0; url=./docs/">
<a href="./docs/">API docs</a>
EOF
}

build_swagger() {
  local docs_dir="$1"
  mkdir -p "$docs_dir"
  cp "$openapi_abs" "$docs_dir/openapi.json"

  for name in swagger-ui-bundle.js swagger-ui.css favicon-32x32.png; do
    curl -fsSL --proto '=https' --tlsv1.2 "${CDN_BASE}/${name}" -o "${docs_dir}/${name}"
  done

  # Relative URLs; Try it out disabled (no live API from Pages).
  cat >"$docs_dir/index.html" <<EOF
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <title>${title}</title>
  <link rel="stylesheet" type="text/css" href="./swagger-ui.css">
  <link rel="icon" type="image/png" href="./favicon-32x32.png" sizes="32x32">
  <style>
    html { box-sizing: border-box; overflow-y: scroll; }
    *, *:before, *:after { box-sizing: inherit; }
    body { margin: 0; background: #fafafa; }
  </style>
</head>
<body>
  <div id="swagger-ui"></div>
  <script src="./swagger-ui-bundle.js"></script>
  <script>
    window.onload = function () {
      window.ui = SwaggerUIBundle({
        url: "./openapi.json",
        dom_id: "#swagger-ui",
        deepLinking: true,
        presets: [SwaggerUIBundle.presets.apis],
        plugins: [SwaggerUIBundle.plugins.DownloadUrl],
        layout: "BaseLayout",
        supportedSubmitMethods: []
      });
    };
  </script>
</body>
</html>
EOF
}

build_redocly() {
  local docs_dir="$1"
  mkdir -p "$docs_dir"
  cp "$openapi_abs" "$docs_dir/openapi.json"

  if ! command -v npx >/dev/null 2>&1; then
    echo "error: npx is required for --renderer redocly (install Node.js)" >&2
    return 1
  fi

  # Self-contained HTML via Redocly CLI (pinned).
  npx --yes "@redocly/cli@${REDOCLY_CLI_VERSION}" build-docs "$openapi_abs" \
    --output "$docs_dir/index.html" \
    --title "$title" \
    --disableGoogleFont
}

case "$renderer" in
  swagger)
    build_swagger "$out/docs"
    ;;
  redocly)
    build_redocly "$out/docs"
    ;;
  both)
    build_swagger "$out/docs"
    build_redocly "$out/redoc"
    ;;
  *)
    echo "error: unexpected renderer: $renderer" >&2
    exit 2
    ;;
esac

write_root_files
echo "built site at $out (renderer=$renderer)"
