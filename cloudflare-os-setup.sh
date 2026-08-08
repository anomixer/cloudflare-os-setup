#!/usr/bin/env bash
# One-shot Cloudflare OS setup script for a new machine.
#
#   1. Install Git, Node.js, and pnpm.
#   2. Clone or update the cloudflare-os source tree.
#   3. Apply the LAN patch when requested.
#   4. Install dependencies.
#   5. Start the local server.
#
# Usage:
#   bash cloudflare-os-setup.sh          Local-only mode: http://localhost:8787
#   bash cloudflare-os-setup.sh --lan    LAN mode: http://<local-ip>:8787
#
# Optional environment overrides:
#   REPO_URL=... TARGET_DIR=... NODE_VERSION=... PNPM_VERSION=...
set -euo pipefail

LAN=0
for arg in "$@"; do
  case "$arg" in
    --lan) LAN=1 ;;
    *) echo "Unknown argument: $arg"; echo "Usage: bash cloudflare-os-setup.sh [--lan]"; exit 1 ;;
  esac
done

REPO_URL="${REPO_URL:-https://github.com/cloudflare/cloudflare-os.git}"
TARGET_DIR="${TARGET_DIR:-$HOME/cloudflare-os}"
NODE_VERSION="${NODE_VERSION:-v24.19.0}"
PNPM_VERSION="${PNPM_VERSION:-11.17.0}"

say() { echo "==> $*"; }

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
if [ -f "$SCRIPT_DIR/pnpm-workspace.yaml" ] && [ -d "$SCRIPT_DIR/packages" ]; then
  TARGET_DIR="$SCRIPT_DIR"
  say "Detected execution inside a cloudflare-os repository; using $TARGET_DIR"
fi

if ! command -v git >/dev/null 2>&1; then
  say "Installing Git"
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
    echo "Could not find apt, dnf, yum, pacman, or brew. Install Git manually and run again."; exit 1
  fi
else
  say "Git already installed: $(git --version)"
fi

for cmd in curl tar; do
  command -v "$cmd" >/dev/null 2>&1 || { echo "Required command not found: $cmd. Install it first."; exit 1; }
done

if ! command -v node >/dev/null 2>&1; then
  case "$(uname -m)" in
    x86_64) ARCH="x64" ;;
    aarch64) ARCH="arm64" ;;
    *) echo "Unsupported architecture: $(uname -m)"; exit 1 ;;
  esac
  DEST="$HOME/.local/node"
  say "Installing Node.js $NODE_VERSION ($ARCH) to $DEST"
  mkdir -p "$DEST"
  curl -fsSL "https://nodejs.org/dist/$NODE_VERSION/node-$NODE_VERSION-linux-$ARCH.tar.xz" \
    | tar -xJ --strip-components=1 -C "$DEST"
  export PATH="$DEST/bin:$PATH"
  grep -q '.local/node/bin' "$HOME/.bashrc" 2>/dev/null \
    || echo 'export PATH="$HOME/.local/node/bin:$PATH"' >> "$HOME/.bashrc"
else
  say "Node.js already installed: $(node --version)"
fi

command -v npm >/dev/null 2>&1 || { echo "npm was not found. Check the Node.js installation."; exit 1; }
if ! command -v pnpm >/dev/null 2>&1; then
  say "Installing pnpm $PNPM_VERSION"
  npm install -g "pnpm@$PNPM_VERSION"
else
  say "pnpm already installed: $(pnpm --version)"
fi

if [ -d "$TARGET_DIR/.git" ]; then
  say "Updating $TARGET_DIR"
  git -C "$TARGET_DIR" pull --ff-only
elif [ -d "$TARGET_DIR" ]; then
  echo "$TARGET_DIR exists but is not a Git repository. Move or remove it before trying again."; exit 1
else
  say "Cloning $REPO_URL"
  git clone "$REPO_URL" "$TARGET_DIR"
fi
cd "$TARGET_DIR"

# Apply the LAN patch after clone/update. The patch is intentionally kept here so
# the upstream checkout remains the source of truth.
say "Checking the run-dev-server.js LAN patch"
if grep -q 'const isLan = process.argv.includes(\"--lan\")' run-dev-server.js; then
  say "LAN patch already applied; skipping"
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
    say "LAN patch applied"
  else
    echo "Warning: could not apply the LAN patch. The upstream run-dev-server.js may have changed."
    echo "         The server can still start, but --lan and --ip may not work."
  fi
  rm -f "$LAN_PATCH"
fi

say "Installing dependencies"
pnpm install

if [ "$LAN" = "1" ]; then
  IP=$(hostname -I 2>/dev/null | awk '{print $1}')
  say "Starting pnpm run-local -- --lan"
  echo "     Local:   http://localhost:8787"
  [ -n "$IP" ] && echo "     LAN:     http://$IP:8787"
  pnpm run-local -- --lan
else
  say "Starting pnpm run-local"
  echo "     URL: http://localhost:8787 (use --lan for LAN access)"
  pnpm run-local
fi
