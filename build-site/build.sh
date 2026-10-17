#!/usr/bin/env bash
# Build a static Swagger UI site from an OpenAPI document.
# Usage:
#   build.sh --openapi FILE --out DIR [--title TITLE]
set -euo pipefail

# Pin swagger-ui-dist; bump intentionally when upgrading the UI.
SWAGGER_UI_VERSION="${SWAGGER_UI_VERSION:-5.18.3}"
CDN_BASE="https://cdn.jsdelivr.net/npm/swagger-ui-dist@${SWAGGER_UI_VERSION}"

openapi=""
out=""
title="API docs"

usage() {
  echo "Usage: $0 --openapi FILE --out DIR [--title TITLE]" >&2
  exit 2
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --openapi) openapi="${2:-}"; shift 2 ;;
    --out) out="${2:-}"; shift 2 ;;
    --title) title="${2:-}"; shift 2 ;;
    -h|--help) usage ;;
    *) echo "unknown arg: $1" >&2; usage ;;
  esac
done

[[ -n "$openapi" && -n "$out" && -f "$openapi" ]] || usage

out="$(mkdir -p "$out" && cd "$out" && pwd -P)"
docs_dir="$out/docs"
mkdir -p "$docs_dir"

cp "$openapi" "$docs_dir/openapi.json"

for name in swagger-ui-bundle.js swagger-ui.css favicon-32x32.png; do
  curl -fsSL "${CDN_BASE}/${name}" -o "${docs_dir}/${name}"
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

: >"$out/.nojekyll"
cat >"$out/index.html" <<'EOF'
<!DOCTYPE html><meta http-equiv="refresh" content="0; url=./docs/">
<a href="./docs/">API docs</a>
EOF

echo "built site at $out"
