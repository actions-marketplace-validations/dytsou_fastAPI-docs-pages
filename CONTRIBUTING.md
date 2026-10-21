# Contributing to [fastAPI-docs-pages](https://github.com/dytsou/fastAPI-docs-pages)

We love your input! We want to make contributing to this project as easy and transparent as possible, whether it's:

- Reporting [an issue](https://github.com/dytsou/fastAPI-docs-pages/issues/new).
- Discussing the current state of the code.
- Submitting [a fix](https://github.com/dytsou/fastAPI-docs-pages/compare).
- Proposing [new features](https://github.com/dytsou/fastAPI-docs-pages/issues/new).
- Becoming a maintainer.

Please also read our [Code of Conduct](CODE_OF_CONDUCT.md).

## All Changes Happen Through Pull Requests

Pull requests are the best way to propose changes. We actively welcome your pull requests:

1. Fork the repo and create your branch from `main`.
2. If you've added code that should be tested, extend `tests/smoke.sh` (or add focused checks).
3. If you've changed workflow inputs, composite actions, or URLs, update the documentation (`README.md` / `README-zh.md`, and release notes template if needed).
4. Run the smoke tests locally (see [Local development](#local-development)).
5. Open that pull request!

## Under the hood

This repository is a set of **composite GitHub Actions** plus a **reusable workflow** that:

1. Runs a consumer `export-command` on the default branch and each open same-repo PR worktree.
2. Builds a static site from the resulting OpenAPI JSON (`swagger`, `redocly`, or `both`).
3. Deploys the site to GitHub Pages, upserts preview links on the PR body, and prunes Deployments history for the active ref.

Primary entry for consumers:

`dytsou/fastAPI-docs-pages/.github/workflows/publish.yml@v1`

Layout:

| Path | Role |
| ---- | ---- |
| `build-site/` | OpenAPI JSON → static docs |
| `assemble/` | Main + PR preview trees |
| `upsert-pr-body/` | PR description link block |
| `upsert-deployments/` | Prune GitHub Deployments history for a ref |
| `.github/workflows/publish.yml` | Thin reusable workflow (build → deploy → PR body) |
| `.github/workflows/release.yml` | Semver tag → GitHub Release + major tag |

## Local development

1. Fork the repository and clone it to your machine.
2. From the repository root, run:

```bash
bash tests/smoke.sh
```

This checks PR-body upsert logic and builds Swagger / Redocly / both renderers (Redocly needs Node.js 26+ / `npx` on your PATH).

3. Optional: build a site from a local OpenAPI file:

```bash
./build-site/build.sh \
  --openapi /path/to/openapi.json \
  --out /tmp/api-docs-site \
  --title "My API" \
  --renderer both
```

Then serve the output directory and open `/docs/` (and `/redoc/` when using `both`).

> [!NOTE]
> End-to-end Pages deploy and PR-body upsert need a real GitHub repository and tokens; those paths are exercised in consumer CI via the reusable workflow.

## Any contributions you make will be under the MIT Software License

In short, when you submit changes, your submissions are understood to be under the same [MIT License](https://choosealicense.com/licenses/mit/) that covers the project. Feel free to contact the maintainers if that's a concern.

## Report issues/bugs using GitHub's [issues](https://github.com/dytsou/fastAPI-docs-pages/issues)

We use GitHub issues to track public bugs. Report a bug by [opening a new issue](https://github.com/dytsou/fastAPI-docs-pages/issues/new); it's that easy!

### Bug reports

**Great bug reports** tend to have:

- A quick summary and/or background
- Steps to reproduce
  - Be specific!
  - Share the consumer workflow YAML (redact secrets)
  - Link the failing Actions run, if possible
- What actually happens
- What you expected would happen
- Notes (including renderer: `swagger` / `redocly` / `both`, and anything you already tried)

### Feature requests

**Great feature requests** tend to have:

- A quick idea summary
- What & why you want to add the specific feature
- Additional context such as screenshots, OpenAPI samples, or links to related tools
