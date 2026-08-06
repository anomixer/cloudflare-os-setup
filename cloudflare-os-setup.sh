#!/usr/bin/env bash
# Cloudflare OS 全新機器一鍵安裝腳本
#
#   1. 安裝 git、Node.js、pnpm
#   2. 下載/更新 cloudflare-os 原始碼
#   3. pnpm install 安裝依賴
#   4. pnpm run-local 啟動 server
#
# 用法:
#   bash install-run-local.sh            本機使用: http://localhost:8787
#   bash install-run-local.sh --lan      區網使用: http://<本機IP>:8787
#
# 環境變數覆寫（選擇性）:
#   REPO_URL=...  TARGET_DIR=...  NODE_VERSION=...  PNPM_VERSION=...
set -euo pipefail

LAN=0
for arg in "$@"; do
  case "$arg" in
    --lan) LAN=1 ;;
    *) echo "未知參數: $arg"; echo "用法: bash install-run-local.sh [--lan]"; exit 1 ;;
  esac
done

REPO_URL="${REPO_URL:-https://github.com/cloudflare/cloudflare-os.git}"
TARGET_DIR="${TARGET_DIR:-$HOME/cloudflare-os}"
NODE_VERSION="${NODE_VERSION:-v24.19.0}"     # Node 24 LTS
PNPM_VERSION="${PNPM_VERSION:-11.17.0}"      # 與 repo package.json 的 packageManager 一致

say() { echo "==> $*"; }

# ---------------------------------------------------------------------------
# 若腳本本身放在 cloudflare-os repo 內（有 pnpm-workspace.yaml 的 git 目錄），
# 就直接用當前目錄，不再 clone。
# ---------------------------------------------------------------------------
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
if [ -f "$SCRIPT_DIR/pnpm-workspace.yaml" ] && [ -d "$SCRIPT_DIR/packages" ]; then
  TARGET_DIR="$SCRIPT_DIR"
  say "偵測到在 cloudflare-os repo 內執行，使用 $TARGET_DIR"
fi

# ---------------------------------------------------------------------------
# 1. git
# ---------------------------------------------------------------------------
if ! command -v git >/dev/null 2>&1; then
  say "安裝 git"
  if command -v apt-get >/dev/null 2>&1; then
    sudo apt-get update && sudo apt-get install -y git
  elif command -v dnf >/dev/null 2>&1; then
    sudo dnf install -y git
  elif command -v yum >/dev/null 2>&1; then
    sudo yum install -y git
  elif command -v pacman >/dev/null 2>&1; then
    sudo pacman -Sy --noconfirm git
  elif command -v brew >/dev/null 2>&1; then
    brew install git
  else
    echo "找不到 apt/dnf/yum/pacman/brew，無法自動安裝 git，請手動安裝後重跑。"; exit 1
  fi
else
  say "git 已存在: $(git --version)"
fi

for cmd in curl tar; do
  command -v "$cmd" >/dev/null 2>&1 || { echo "缺少 $cmd，請先安裝。"; exit 1; }
done

# ---------------------------------------------------------------------------
# 2. Node.js（裝到 ~/.local/node，不需 root）
# ---------------------------------------------------------------------------
if ! command -v node >/dev/null 2>&1; then
  case "$(uname -m)" in
    x86_64) ARCH="x64" ;;
    aarch64) ARCH="arm64" ;;
    *) echo "不支援的架構: $(uname -m)"; exit 1 ;;
  esac
  DEST="$HOME/.local/node"
  say "安裝 Node.js $NODE_VERSION ($ARCH) 到 $DEST"
  mkdir -p "$DEST"
  curl -fsSL "https://nodejs.org/dist/$NODE_VERSION/node-$NODE_VERSION-linux-$ARCH.tar.xz" \
    | tar -xJ --strip-components=1 -C "$DEST"
  export PATH="$DEST/bin:$PATH"
  grep -q '.local/node/bin' "$HOME/.bashrc" 2>/dev/null \
    || echo 'export PATH="$HOME/.local/node/bin:$PATH"' >> "$HOME/.bashrc"
else
  say "node 已存在: $(node --version)"
fi

# ---------------------------------------------------------------------------
# 3. pnpm（透過 npm 裝 repo 指定的版本）
# ---------------------------------------------------------------------------
command -v npm >/dev/null 2>&1 || { echo "找不到 npm，請確認 Node.js 安裝正確。"; exit 1; }
if ! command -v pnpm >/dev/null 2>&1; then
  say "安裝 pnpm $PNPM_VERSION"
  npm install -g "pnpm@$PNPM_VERSION"
else
  say "pnpm 已存在: $(pnpm --version)"
fi

# ---------------------------------------------------------------------------
# 4. clone / 更新 cloudflare-os
# ---------------------------------------------------------------------------
if [ -d "$TARGET_DIR/.git" ]; then
  say "更新 $TARGET_DIR"
  git -C "$TARGET_DIR" pull --ff-only
elif [ -d "$TARGET_DIR" ]; then
  echo "$TARGET_DIR 已存在但不是 git repo，請搬走或刪掉後重跑。"; exit 1
else
  say "clone $REPO_URL"
  git clone "$REPO_URL" "$TARGET_DIR"
fi
cd "$TARGET_DIR"

# ---------------------------------------------------------------------------
# 5. 安裝依賴
# ---------------------------------------------------------------------------
say "pnpm install"
pnpm install

# ---------------------------------------------------------------------------
# 6. 啟動 server（佔住終端；Ctrl+C 結束）
# ---------------------------------------------------------------------------
if [ "$LAN" = "1" ]; then
  IP=$(hostname -I 2>/dev/null | awk '{print $1}')
  say "pnpm run-local -- --lan"
  echo "     本機:   http://localhost:8787"
  [ -n "$IP" ] && echo "     同網段: http://$IP:8787"
  pnpm run-local -- --lan
else
  say "pnpm run-local"
  echo "     網址: http://localhost:8787（要用區網請加 --lan）"
  pnpm run-local
fi
