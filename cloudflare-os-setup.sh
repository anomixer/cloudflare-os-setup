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
# 4.5 套用 run-dev-server.js 的 LAN patch（upstream repo 尚未包含 --lan 支援）
# ---------------------------------------------------------------------------
say "檢查 run-dev-server.js LAN patch"
if grep -q 'const isLan = process.argv.includes("--lan")' run-dev-server.js; then
  say "  已套用，跳過"
else
  LAN_PATCH="$(mktemp)"
  cat > "$LAN_PATCH" <<'PATCH'
diff --git a/run-dev-server.js b/run-dev-server.js
index a5aba89..022bfde 100644
--- a/run-dev-server.js
+++ b/run-dev-server.js
@@ -13,6 +13,7 @@
 import { existsSync, readFileSync, writeFileSync, readdirSync, statSync } from "node:fs";
 import { execFileSync, spawn } from "node:child_process";
 import { join, dirname } from "node:path";
+import { networkInterfaces } from "node:os";
 import { fileURLToPath } from "node:url";
 import { parse } from "jsonc-parser";
 import { getWranglerPortFromBackendHost } from "./scripts/dev-server-config.js";
@@ -45,6 +46,25 @@ loadDevVars();
 
 const useWorkersAi = process.argv.includes("--use-workers-ai-binding");
 
+// By default Wrangler binds to 127.0.0.1, which is fine for local-only access. Pass
+// `--lan` (or `--ip 0.0.0.0` directly) to also accept connections from the local network.
+const isLan = process.argv.includes("--lan");
+const devIpIndex = process.argv.indexOf("--ip");
+const devIp = devIpIndex !== -1 ? process.argv[devIpIndex + 1] : (isLan ? "0.0.0.0" : undefined);
+
+// The origin LAN clients use to reach this server (e.g. http://172.16.21.31:8787). In `--lan` mode it
+// is auto-detected from the first non-internal interface. Override with `--public-url <origin>`.
+const publicUrlIndex = process.argv.indexOf("--public-url");
+let publicUrl = publicUrlIndex !== -1 ? process.argv[publicUrlIndex + 1] : undefined;
+if (isLan && publicUrl === undefined) {
+  const lanIp = Object.values(networkInterfaces())
+      .flat()
+      .find(iface => iface && !iface.internal && iface.family === "IPv4")?.address;
+  const portArgIndex = process.argv.indexOf("--port");
+  const port = portArgIndex !== -1 ? process.argv[portArgIndex + 1] : "8787";
+  if (lanIp) publicUrl = `http://${lanIp}:${port}`;
+}
+
 // Generate the format blueprint module before Wrangler tries to bundle the backend. The output is
 // gitignored, so it will not exist on a clean checkout.
 execFileSync(
@@ -215,6 +235,22 @@ for (const gk of gatekeepers) {
     }
   }
 
+  // In LAN mode the gatekeepers must advertise an origin LAN clients can reach, not the
+  // localhost default baked into each Worker's `env.BASE_URL ?? "http://localhost:8787/..."`.
+  // Without this, OAuth redirects (and generated URLs) point back at the client's own
+  // localhost and the connect flow breaks. A `BASE_URL` set in the gatekeeper's own config
+  // still wins.
+  if (publicUrl) {
+    config.vars = config.vars || {};
+    if (config.vars.BASE_URL === undefined) {
+      // The router serves each gatekeeper at /gatekeeper/<short>, where <short> is the service
+      // binding name (GATEKEEPER_GITHUB) minus the prefix, lowercased.
+      const routeSuffix =
+          bindingName(gk).slice("GATEKEEPER_".length).toLowerCase().replaceAll("_", "-");
+      config.vars.BASE_URL = `${publicUrl}/gatekeeper/${routeSuffix}`;
+    }
+  }
+
   const outPath = join(gk.dir, "wrangler.dev.jsonc");
   writeFileSync(outPath, JSON.stringify(config, null, 2) + "\n");
   console.log(`generated: ${outPath}`);
@@ -301,6 +337,7 @@ const configs = [
 ];
 
 const args = configs.flatMap(c => ["-c", c]);
+if (devIp) args.push("--ip", devIp);
 const backendHost = process.env.VITE_BACKEND_HOST;
 if (backendHost) {
   let wranglerPort;
PATCH
  if git apply --check "$LAN_PATCH" 2>/dev/null; then
    git apply "$LAN_PATCH"
    say "  LAN patch 已套用"
  else
    echo "警告: LAN patch 無法套用（upstream 的 run-dev-server.js 可能已變更）。"
    echo "      server 仍可啟動，但 --lan / --ip 不會作用。"
  fi
  rm -f "$LAN_PATCH"
fi

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
