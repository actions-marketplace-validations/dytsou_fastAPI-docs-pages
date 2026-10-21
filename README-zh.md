# FastAPI Docs Pages

把靜態 API 文件（Swagger UI 與／或 Redocly）發到 GitHub Pages：涵蓋 `main` 與每個同 repo PR，並把預覽連結加到 PR 描述結尾。

![GitHub release](https://img.shields.io/github/v/release/dytsou/fastAPI-docs-pages)
![CI](https://github.com/dytsou/fastAPI-docs-pages/actions/workflows/ci.yml/badge.svg)
![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)

[English](README.md) · [繁體中文](README-zh.md)

## 目錄

- [快速開始](#快速開始)
- [用 path filters 省 CI](#用-path-filters-省-ci)
- [網址](#網址)
- [Renderers](#renderers)
- [Workflow 輸入](#workflow-輸入)
- [匯出契約](#匯出契約)
- [Composite actions](#composite-actions)
- [部署](#部署)
- [支援](#支援)
- [貢獻](#貢獻)
- [重要說明](#重要說明)

## 快速開始

1. **開啟 GitHub Pages** — Settings → Pages → Source: **GitHub Actions**。可依需要保護 `github-pages` Environment。
2. **加入 caller workflow**（把 export 指令換成你專案寫出 OpenAPI JSON 的方式）：  
可依專案目錄調整 glob（例如 `src/**`、`app/**`）。`workflow_dispatch` 不要加 `paths`，方便手動強制重建。

```yaml
# .github/workflows/api-docs-pages.yml
name: API Docs Pages

# 建議加 path filters，只在 OpenAPI 來源有變時重建
on:
  push:
    branches: [main]
    paths:
      - "backend/**"                           # 擁有 OpenAPI schema 的應用
      - ".github/workflows/api-docs-pages.yml" # caller 本身變更時也要重跑
  pull_request:
    types: [opened, synchronize, reopened, closed]
    paths:
      - "backend/**"
      - ".github/workflows/api-docs-pages.yml"
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

3. **Workflow 通過後打開預覽** — 見 [網址](#網址)。

### 基本用法

只需提供 `export-command`。預設在 tree 根目錄寫入 `openapi.json`：

```yaml
jobs:
  api-docs:
    uses: dytsou/fastAPI-docs-pages/.github/workflows/publish.yml@v1
    with:
      export-command: ./scripts/export-openapi.sh
```

### 範例（FastAPI + uv）

工具鏈裝在 primary checkout；被建置的 app 程式碼來自各個 git tree：

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

## 網址


| 用途                             | 路徑                                                         |
| ------------------------------ | ---------------------------------------------------------- |
| Main（預設 docs）                  | `https://<owner>.github.io/<repo>/docs/`                   |
| Main（Redocly，`renderer: both`） | `https://<owner>.github.io/<repo>/redoc/`                  |
| 同 repo PR                      | `https://<owner>.github.io/<repo>/pr-preview/pr-<n>/docs/` |


部署後，同 repo PR 會在描述**結尾**追加連結（由 CI 管理 marker；不必在 PR template 預留）。

## Renderers

在 reusable workflow（或 `build-site` / `assemble`）設定 `renderer`：


| 值             | 輸出                                        |
| ------------- | ----------------------------------------- |
| `swagger`（預設） | `/docs/` 為 Swagger UI                     |
| `redocly`     | `/docs/` 為 Redocly HTML                   |
| `both`        | `/docs/` 為 Swagger UI，`/redoc/` 為 Redocly |


Redocly 建置使用 pinned 的 `@redocly/cli`（經 `npx`；需要時會自動 setup Node.js）。

### 範例（只建 Redocly）

```yaml
with:
  export-command: ./scripts/export-openapi.sh
  renderer: redocly
```

## Workflow 輸入

Reusable workflow：`dytsou/fastAPI-docs-pages/.github/workflows/publish.yml@v1`


| 名稱                  | 必填  | 預設             | 說明                                     |
| :------------------- | :--- | :-------------- | :-------------------------------------- |
| `export-command`    | 是   | —              | 為當前 tree 寫出 `openapi-path` 的 shell     |
| `openapi-path`      | 否   | `openapi.json` | 相對於各 tree 根目錄的 OpenAPI 路徑              |
| `working-directory` | 否   | `.`            | 執行 `export-command` 的目錄（相對 tree 根）     |
| `setup-command`     | 否   | *(空)*          | 在 primary checkout 做一次的準備（如 `uv sync`） |
| `title`             | 否   | `API docs`     | 文件頁 HTML title                         |
| `renderer`          | 否   | `swagger`      | `swagger`、`redocly` 或 `both`           |
| `pages-out`         | 否   | `_site`        | 上傳為 Pages artifact 的目錄                 |


## 匯出契約

對每個 git tree（default branch + 開啟中的同 repo PR），workflow 會執行 `export-command`，並帶入：


| Env                  | 意義                                           |
| -------------------- | -------------------------------------------- |
| `API_DOCS_TREE_ROOT` | 該 tree worktree 的絕對路徑                        |
| `API_DOCS_WORKSPACE` | Primary `actions/checkout` workspace（工具鏈裝這裡） |


`export-command` 必須寫出 `openapi-path`（相對 tree 根目錄）。此 action **不會** import 你的應用程式。

## Composite actions

優先使用 reusable workflow。需要自訂 deploy 流程時再用：


| Action                                        | 用途                      |
| --------------------------------------------- | ----------------------- |
| `dytsou/fastAPI-docs-pages/build-site@v1`     | 單一 `openapi.json` → 靜態站 |
| `dytsou/fastAPI-docs-pages/assemble@v1`       | Main + PR 預覽            |
| `dytsou/fastAPI-docs-pages/upsert-pr-body@v1` | 追加／更新 PR body 連結        |
| `dytsou/fastAPI-docs-pages/upsert-deployments@v1` | 修剪某 ref 的 Deployments 紀錄（`replace` / `purge`） |
| `dytsou/fastAPI-docs-pages@v1`                | `build-site` 別名         |


### 基本用法（`build-site`）

```yaml
- uses: dytsou/fastAPI-docs-pages/build-site@v1
  with:
    openapi-path: ./openapi.json
    out: _site
    title: My API
```

## 部署

### 前置條件

1. 消費者 repo 的 Pages Source 設為 GitHub Actions
2. 能對任意相關 git ref 產出合法 OpenAPI 3 JSON 的指令
3. Workflow 權限：`contents: read`、`pages: write`、`id-token: write`，以及 `pull-requests: write`（PR body 連結）

### Deployments 紀錄

每次 Pages 部署成功後，reusable workflow 會呼叫
`upsert-deployments`，避免 GitHub Deployments UI 對同一 ref 累積多張卡片：

- **push／開啟中 PR 同步：** `mode: replace` — 保留該分支最新的 `github-pages`
  deployment；刪除同一 ref 的較舊 deployment
- **PR 關閉：** `mode: purge` — 刪除該 PR head 分支的所有 `github-pages` deployment

其他 ref（含仍開啟的 PR）不受影響。API 失敗採 soft-fail，文件發佈仍會維持綠燈。
Job 使用的權限：`deployments: write`（在 `publish.yml` 內設定；僅使用 reusable
workflow 的 caller 無需在頂層額外設定 deployments 權限）。

### 本機 smoke（本 repo）

```bash
bash tests/smoke.sh
```

## 支援

若無法運作：

- 確認 Pages Source 為 **GitHub Actions**，且 `github-pages` environment 允許部署
- 確認 `export-command` 在每個 worktree 內寫出 `openapi-path`（見 [匯出契約](#匯出契約)）
- 開 [issue](https://github.com/dytsou/fastAPI-docs-pages/issues) 並附上失敗的 workflow run（請遮罩密鑰）

### 常見狀況


| 現象                               | 可能原因                             |
| -------------------------------- | -------------------------------- |
| PR 上 build 被跳過                   | Fork／跨 repo PR（v1 不支援）           |
| `export-command did not write …` | `openapi-path` 與實際寫入路徑不一致        |
| Swagger 空白或壞掉                    | export 產出的 OpenAPI JSON 無效       |
| PR body 沒變                       | 缺少 `pull-requests: write`，或內容已相同 |


## 貢獻

歡迎貢獻 — 請見 [CONTRIBUTING.md](CONTRIBUTING.md) 與 [Code of Conduct](CODE_OF_CONDUCT.md)。也歡迎 star、[開 issue](https://github.com/dytsou/fastAPI-docs-pages/issues) 或送 PR。

## 重要說明

> [!IMPORTANT]
> **不處理 fork PR。** 只有 `head.repo` 為本 repo 時才會發佈預覽並更新 PR body。

> [!WARNING]
> 靜態站已關閉 Swagger **Try it out**。Pages 只提供文件預覽，不會代理你的線上 API。

## License

This project is open source and available under the [MIT License](LICENSE).