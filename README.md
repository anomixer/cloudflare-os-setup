# Cloudflare OS — 本地安裝與 LAN 設定（本次改動）

本文記錄對本 repo 的兩處改動：

1. `cloudflare-os-setup.sh`：全新機器一鍵安裝腳本
2. `run-dev-server.js`：新增 `--lan` 模式，讓整個 stack（含 Gatekeeper）可從區網存取

原專案官方說明已由 git 歷史保留（`git show HEAD:README.md` 可回復）。

---

## 背景：為什麼有這個腳本

Cloudflare OS 官方 README 的 Quick Start 只有一句話——「裝好 pnpm，然後 `pnpm run-local`」。
它假設你的機器已經有能用的 Node.js、正確版本的 pnpm、以及 LAN 環境不用管。
實際上線後，[upstream 的 Issues](https://github.com/cloudflare/cloudflare-os/issues) 累積了一堆
第一天上手的踩雷，例如：

- **`pnpm crash during initial run`（#15）**：第一次 `pnpm install` 時 sharp / esbuild / workerd
  等 postinstall 直接爆掉。最常見的原因就是**機器上根本沒有 Node.js**（`node: not found`），
  但 README 沒說要先裝。
- **`pnpm run-local cannot start on Windows`（#19）**：`run-local` 用 `execFileSync("pnpm", ...)`，
  依賴 `pnpm` 在 PATH 上且能直接被 spawn；環境不同就 ENOENT。
- **`Can we please get some getting started docs?`（#25）**：新手希望有一份「從零到能跑」的完整
  步驟，而不是一行指令。
- 此外，若用**非 repo 指定版本**的 pnpm 跑 install，還會踩
  `ERR_PNPM_INVALID_SELECTOR Cannot parse the "^sharp" selector` 這類解析 bug（見
  `pnpm-workspace.yaml` 的 `allowBuilds` / `minimumReleaseAge`），因為該語法有版本限制。

本腳本把這些一次解決：自動裝 git / Node / pnpm（版本鎖定與 repo 一致）、clone 最新原始碼、
套上 LAN patch、`pnpm install`、然後啟動。你只需要會跑一條指令。

> **這個腳本是過渡方案。** 等原廠把上面的 issue 解掉（例如把 Node 安裝、pnpm 版本、以及
> LAN 綁定都處理好），本腳本就沒有存在必要了。現在想先體驗的人，可以用這支腳本擋著用。

---

## 一、`cloudflare-os-setup.sh`（一鍵安裝）

### 功能

在全新的 Linux 機器上依序完成：

1. 安裝 `git`（自動偵測 apt / dnf / yum / pacman / brew）
2. 安裝 Node.js v24.19.0 LTS 到 `~/.local/node`（不需 root，並寫入 `~/.bashrc` 的 PATH）
3. 安裝 pnpm 11.17.0（與 repo `package.json` 的 `packageManager` 一致）
4. clone / 更新 `cloudflare-os` 原始碼（預設 `~/cloudflare-os`）
5. **自動套用 `run-dev-server.js` 的 LAN patch**（upstream 尚未包含，見下）
6. `pnpm install` 安裝依賴（含 sharp / esbuild / workerd 等 postinstall）
7. `pnpm run-local` 啟動本地 server

### 用法

```bash
# 本機使用
bash cloudflare-os-setup.sh

# 區網使用（見下面 LAN 說明）
bash cloudflare-os-setup.sh --lan
```

啟動後網址：本機 `http://localhost:8787`；`--lan` 模式會順便印出同網段網址。

### 可覆寫的環境變數

| 變數 | 預設 | 說明 |
|------|------|------|
| `REPO_URL` | `https://github.com/cloudflare/cloudflare-os.git` | 要 clone 的 repo |
| `TARGET_DIR` | `~/cloudflare-os` | 放原始碼的目錄 |
| `NODE_VERSION` | `v24.19.0` | Node.js 版本 |
| `PNPM_VERSION` | `11.17.0` | pnpm 版本 |

### 注意事項

- 若腳本放在 cloudflare-os repo 目錄內執行，會自動偵測並直接用目前目錄，不會再 clone。
- 若 `TARGET_DIR` 已存在但**不是** git repo，腳本會中止並要求先搬走/刪除。
- clone 來源是 **upstream** `cloudflare/cloudflare-os`，不會包含本專案的 `run-dev-server.js` LAN
  改動，所以腳本在 clone/更新後會自動用內嵌的 patch 套上去：
  - 已套過（偵測到 `--lan`）就跳過；
  - 套不上（upstream 未來改了該檔）會印出警告但不會中止，只是 `--lan` 不作用。
- 對已有 repo 使用 `git pull --ff-only` 更新；若上游改動與本地 patch 衝突，會需手動處理。

---

## 二、`run-dev-server.js` 的 `--lan` 模式

### 問題

本地模式（`wrangler dev`）預設只綁定 `127.0.0.1`，且每個 Gatekeeper Worker 的
`env.BASE_URL` 都預設為 `http://localhost:8787/gatekeeper/<name>`。這導致：

- 從區網其他裝置連不進來（只綁定 localhost）；
- 就算綁定 `0.0.0.0`，Gatekeeper 的 **OAuth redirect 仍會導向 client 自己機器的
  `localhost`**，OAuth 型 Gatekeeper 從區網無法完成連線。

### 改動內容

`run-dev-server.js` 新增三個旗標：

| 旗標 | 作用 |
|------|------|
| `--lan` | 綁定 `0.0.0.0`，並自動偵測區網 IP（`node:os` 第一個非 loopback IPv4） |
| `--ip <ip>` | 指定 wrangler 綁定的 IP（例如 `0.0.0.0`） |
| `--public-url <origin>` | 覆寫 Gatekeeper `BASE_URL` 的 origin（例如 `http://172.16.21.31:8787`） |

`--lan` 模式在產生每個 Gatekeeper 的 `wrangler.dev.jsonc` 時，會自動注入

```
BASE_URL = http://<區網IP>:8787/gatekeeper/<short>
```

其中 `<short>` 與 router 的路徑一致（由 service binding 名稱去掉 `GATEKEEPER_` 前綴後轉小寫，
例如 `GATEKEEPER_GITHUB` → `github`）。Gatekeeper 自己的 config 若有設 `BASE_URL` 則優先保留。

### 使用

```bash
pnpm run-local -- --lan                 # 綁定 0.0.0.0，自動偵測區網 IP
pnpm run-local -- --ip 0.0.0.0 --public-url http://192.168.1.5:8787   # 手動指定
```

透過 `cloudflare-os-setup.sh --lan` 啟動即是 `--lan` 模式。

### OAuth Gatekeeper 的額外設定

`BASE_URL` 只決定 Gatekeeper 產生的網址；OAuth 型 Gatekeeper（GitHub、Google、Notion、
Confluence、Slack、Supabase、ZoomInfo、Cloudflare 等）的 **OAuth app 必須註冊與
`redirect_uri` 完全相符的網址**，否則 OAuth 流程仍會失敗：

```
http://<區網IP>:8787/gatekeeper/<name>/oauth
```

非 OAuth 的 Gatekeeper（例如 Context Library、Scheduler、MCP）不需要額外設定，改完即可從區網使用。

---

## 三、其他環境修復（非 repo 改動）

本次同時修正了本機開發環境缺 Node.js 的問題：裝了 Node 24 LTS 到 `~/.local/node` 並加入
`~/.bashrc` PATH。先前 `pnpm install` 的 postinstall（sharp / esbuild / workerd）全部因
`node: not found` 失敗、`pnpm run-local` 無法啟動，皆因此解決。
