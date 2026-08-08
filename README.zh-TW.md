# Cloudflare OS 本機安裝與區網支援

[English](README.md)

這是一個用來在 [Cloudflare OS](https://github.com/cloudflare/cloudflare-os) upstream 尚未補齊安裝、Windows、文件與區網支援前，協助本機執行的暫時性 setup 與相容性腳本。

> 這是過渡方案。等 upstream 處理好 Node.js 安裝、pnpm 版本、local server port 與 LAN binding 後，本 repo 可能就不再需要。

## 為什麼需要這個 repo

Cloudflare OS upstream 的 quick start 假設機器已經安裝 Node.js 與正確版本的 pnpm，也沒有完整說明區網存取與首次啟動時常見的問題。

相關 upstream issues：

- [#15 — pnpm crash during initial run](https://github.com/cloudflare/cloudflare-os/issues/15)
- [#19 — pnpm run-local cannot start on Windows](https://github.com/cloudflare/cloudflare-os/issues/19)
- [#25 — Getting started documentation](https://github.com/cloudflare/cloudflare-os/issues/25)
- [#86 — local port and LAN URL handling](https://github.com/cloudflare/cloudflare-os/issues/86)

本 repo 提供一條可重現的安裝路徑，讓 upstream 修復完成前仍能先跑起來。

## 安裝腳本

`cloudflare-os-setup.sh` 會在新的 Linux 機器上依序：

1. 使用可用的套件管理器安裝 Git（`apt`、`dnf`、`yum`、`pacman` 或 Homebrew）。
2. 將 Node.js v24.19.0 LTS 安裝到 `~/.local/node`，不需要 root。
3. 安裝 pnpm 11.17.0。
4. clone 或 fast-forward 更新 upstream `cloudflare/cloudflare-os`。
5. 必要時對 `run-dev-server.js` 套用 LAN patch。
6. 執行 `pnpm install`。
7. 使用 `pnpm run-local` 啟動本地 server。

### 使用方式

先 clone 本 setup repo 並進入目錄：

```bash
git clone https://github.com/anomixer/cloudflare-os-setup.git
cd cloudflare-os-setup
```

接著執行安裝腳本：

```bash
# 僅本機使用
bash cloudflare-os-setup.sh

# 允許區網存取
bash cloudflare-os-setup.sh --lan
```

腳本接著會 clone 或更新 upstream 的 `cloudflare/cloudflare-os`。一般模式網址為 `http://localhost:8787`；`--lan` 模式會額外印出偵測到的區網網址。

## 區網支援

upstream 的本地 server 預設只綁定 localhost，因此同網段的其他裝置無法連線。單純綁定 `0.0.0.0` 也不夠，Gatekeeper 的 OAuth redirect 與產生的 resource URL 必須使用 client 裝置可連線的位址。

Patch 提供以下參數：

| 參數 | 說明 |
| --- | --- |
| `--lan` | 綁定 `0.0.0.0`，並自動偵測非 loopback IPv4 位址 |
| `--ip <ip>` | 手動指定 Wrangler bind address |
| `--public-url <origin>` | 覆寫產生 Gatekeeper URL 時使用的 origin |

例如：

```bash
pnpm run-local -- --lan
pnpm run-local -- --ip 0.0.0.0 --public-url http://192.168.1.5:8787
```

## 限制

- LAN patch 是 clone 後額外套用，目前不是 upstream 的一部分。
- 如果 upstream 修改 `run-dev-server.js`，patch 可能無法自動套用。
- 腳本以 Linux 環境為目標；Windows 使用者建議使用 WSL，或手動套用 upstream 的 Windows 相容性修復。
- 本 repo 不取代 Cloudflare OS 的正式部署文件與 production deployment tooling。
