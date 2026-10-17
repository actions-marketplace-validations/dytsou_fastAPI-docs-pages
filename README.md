# api-docs-pages

Publish a static Swagger UI (`/docs/`) to **GitHub Pages** for `main` and each same-repo PR, and append preview links to the PR description.

Consumers only need to **export OpenAPI JSON** per git ref. This action never imports your app.

## Quick start (reusable workflow)

```yaml
# .github/workflows/api-docs-pages.yml
name: API Docs Pages

on:
  push:
    branches: [main]
  pull_request:
    types: [opened, synchronize, reopened, closed]
  workflow_dispatch:

permissions:
  contents: read
  pages: write
  id-token: write
  pull-requests: write

jobs:
  api-docs:
    uses: dytsou/api-docs-pages/.github/workflows/publish.yml@v1
    with:
      setup-command: |
        cd backend && uv python install 3.13 && uv sync --locked --no-build
      # Tooling from the primary checkout; app code from the tree being built.
      export-command: |
        PYTHONPATH="$API_DOCS_TREE_ROOT/backend" \
          uv run --locked --project "$API_DOCS_WORKSPACE/backend" \
          python scripts/export_openapi.py -o "$API_DOCS_TREE_ROOT/backend/openapi.json"
      openapi-path: backend/openapi.json
      title: My API
```

Enable **Settings → Pages → Source: GitHub Actions**, and optionally protect the `github-pages` environment.

### URLs

| Surface | Path |
|--------|------|
| Main | `https://<owner>.github.io/<repo>/docs/` |
| PR | `https://<owner>.github.io/<repo>/pr-preview/pr-<n>/docs/` |

Fork PRs are skipped. Closing a PR rebuilds without that preview and updates the PR body.

### Export contract

For each git tree (default branch + open same-repo PRs), the workflow runs `export-command` with:

| Env | Meaning |
|-----|---------|
| `API_DOCS_TREE_ROOT` | Absolute path to that tree’s worktree |
| `API_DOCS_WORKSPACE` | Primary `actions/checkout` workspace (good place for installed toolchains) |

`export-command` must write the file at `openapi-path` (relative to the tree root).

## Composite actions

| Action | Purpose |
|--------|---------|
| `dytsou/api-docs-pages/build-site@v1` | One `openapi.json` → static site |
| `dytsou/api-docs-pages/assemble@v1` | Main + PR previews |
| `dytsou/api-docs-pages/upsert-pr-body@v1` | Append/update PR body links |
| `dytsou/api-docs-pages@v1` | Alias of `build-site` |

Prefer the reusable workflow unless you need a custom deploy pipeline.

## Local smoke

```bash
bash tests/smoke.sh
```

## License

MIT
