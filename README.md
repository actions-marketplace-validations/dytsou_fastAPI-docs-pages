# FastAPI Docs Pages

Publish static API docs (Swagger UI and/or Redocly) to GitHub Pages for `main` and each same-repo PR — and append preview links to the PR description.

[![GitHub release](https://img.shields.io/github/v/release/dytsou/fastAPI-docs-pages)](https://github.com/dytsou/fastAPI-docs-pages/releases)
[![CI](https://github.com/dytsou/fastAPI-docs-pages/actions/workflows/ci.yml/badge.svg)](https://github.com/dytsou/fastAPI-docs-pages/actions/workflows/ci.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)

[English](README.md) · [繁體中文](README-zh.md)

## Table of contents

- [Quick Start](#quick-start)
- [URLs](#urls)
- [Renderers](#renderers)
- [Workflow inputs](#workflow-inputs)
- [Export contract](#export-contract)
- [Composite actions](#composite-actions)
- [Deployment](#deployment)
- [Support](#support)
- [Contributing](#contributing)
- [Important Notes](#important-notes)

## Quick Start

1. **Enable GitHub Pages** — Settings → Pages → Source: **GitHub Actions**. Optionally protect the `github-pages` environment.
2. **Add a caller workflow** (replace the export command with how your repo writes OpenAPI JSON):

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
    uses: dytsou/fastAPI-docs-pages/.github/workflows/publish.yml@v1
    with:
      setup-command: |
        cd backend && uv python install 3.13 && uv sync --locked --no-build
      export-command: |
        PYTHONPATH="$API_DOCS_TREE_ROOT/backend" \
          uv run --locked --project "$API_DOCS_WORKSPACE/backend" \
          python scripts/export_openapi.py -o "$API_DOCS_TREE_ROOT/backend/openapi.json"
      openapi-path: backend/openapi.json
      title: My API
```

3. **Open the preview** after the workflow is green — see [URLs](#urls).

### Basic Usage

Only `export-command` is required. Defaults write `openapi.json` at the tree root:

```yaml
jobs:
  api-docs:
    uses: dytsou/fastAPI-docs-pages/.github/workflows/publish.yml@v1
    with:
      export-command: ./scripts/export-openapi.sh
```

### Example (FastAPI + uv)

Tooling stays in the primary checkout; app code comes from each git tree being built:

```yaml
with:
  setup-command: |
    cd backend && uv python install 3.13 && uv sync --locked --no-build
  export-command: |
    PYTHONPATH="$API_DOCS_TREE_ROOT/backend" \
      uv run --locked --project "$API_DOCS_WORKSPACE/backend" \
      python scripts/export_openapi.py -o "$API_DOCS_TREE_ROOT/backend/openapi.json"
  openapi-path: backend/openapi.json
  title: SocratesBot API
  renderer: both
```

## URLs


| Surface | Path |
| ------- | ---- |
| Main (default docs) | `https://<owner>.github.io/<repo>/docs/` |
| Main (Redocly, `renderer: both`) | `https://<owner>.github.io/<repo>/redoc/` |
| Same-repo PR | `https://<owner>.github.io/<repo>/pr-preview/pr-<n>/docs/` |


After deploy, same-repo PRs get these links appended at the **end** of the PR body (CI-owned markers; no template stubs required).

## Renderers

Set `renderer` on the reusable workflow (or `build-site` / `assemble`):


| Value | Output |
| ----- | ------ |
| `swagger` (default) | Swagger UI at `/docs/` |
| `redocly` | Redocly HTML at `/docs/` |
| `both` | Swagger UI at `/docs/` and Redocly at `/redoc/` |

Redocly builds use a pinned `@redocly/cli` via `npx` (Node.js is set up automatically when needed).

### Example (Redocly only)

```yaml
with:
  export-command: ./scripts/export-openapi.sh
  renderer: redocly
```

## Workflow inputs

Reusable workflow: `dytsou/fastAPI-docs-pages/.github/workflows/publish.yml@v1`


| Name | Required | Default | Description |
| :--- | :--- | :--- | :--- |
| `export-command` | Yes | — | Shell that writes `openapi-path` for the current tree |
| `openapi-path` | No | `openapi.json` | OpenAPI file path relative to each tree root |
| `working-directory` | No | `.` | Directory (relative to tree root) where `export-command` runs |
| `setup-command` | No | _(empty)_ | One-time setup in the primary checkout (e.g. `uv sync`) |
| `title` | No | `API docs` | HTML title for the docs page |
| `renderer` | No | `swagger` | `swagger`, `redocly`, or `both` |
| `pages-out` | No | `_site` | Directory uploaded as the Pages artifact |

## Export contract

For each git tree (default branch + open same-repo PRs), the workflow runs `export-command` with:


| Env | Meaning |
| --- | ------- |
| `API_DOCS_TREE_ROOT` | Absolute path to that tree’s worktree |
| `API_DOCS_WORKSPACE` | Primary `actions/checkout` workspace (install toolchains here) |

`export-command` must create the file at `openapi-path` (relative to the tree root). This action never imports your application code.

## Composite actions

Prefer the reusable workflow. Use these when you need a custom deploy pipeline:


| Action | Purpose |
| ------ | ------- |
| `dytsou/fastAPI-docs-pages/build-site@v1` | One `openapi.json` → static site |
| `dytsou/fastAPI-docs-pages/assemble@v1` | Main + PR previews |
| `dytsou/fastAPI-docs-pages/upsert-pr-body@v1` | Append / update PR body links |
| `dytsou/fastAPI-docs-pages@v1` | Alias of `build-site` |

### Basic Usage (`build-site`)

```yaml
- uses: dytsou/fastAPI-docs-pages/build-site@v1
  with:
    openapi-path: ./openapi.json
    out: _site
    title: My API
```

## Deployment

### Prerequisites

1. **Pages source** set to GitHub Actions on the consumer repository
2. A command that can emit valid OpenAPI 3 JSON for any git ref you care about
3. Workflow permissions: `contents: read`, `pages: write`, `id-token: write`, and `pull-requests: write` (for PR body links)

### Local smoke (this repository)

```bash
bash tests/smoke.sh
```

## Support

If something is not working:

- Confirm Pages source is **GitHub Actions** and the `github-pages` environment allowed the deploy
- Check that `export-command` writes `openapi-path` inside each worktree (see [Export contract](#export-contract))
- Open an [issue](https://github.com/dytsou/fastAPI-docs-pages/issues) with the failing workflow run URL (redact secrets)

### When things go wrong


| What you see | Likely cause |
| ------------ | ------------ |
| Build skipped on a PR | Fork / cross-repository PR (not supported in v1) |
| `export-command did not write …` | Path mismatch between `openapi-path` and where the command writes |
| Empty / broken Swagger UI | Invalid OpenAPI JSON from the export step |
| PR body unchanged | Job lacks `pull-requests: write`, or body already matches |

## Contributing

Contributions welcome — star the repo, [open issues](https://github.com/dytsou/fastAPI-docs-pages/issues), or send PRs.

## Important Notes

> [!IMPORTANT]
> **Fork PRs are skipped.** Preview publish and PR body updates run only when `head.repo` is this repository.

> [!WARNING]
> Swagger **Try it out** is disabled on the static site. Pages hosts documentation only; it does not proxy your live API.

## License

This project is open source and available under the [MIT License](LICENSE).
