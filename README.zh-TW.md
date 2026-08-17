# Cloudflare OS 設置腳本

[English README](README.md)

一個簡單的腳本，用於快速設置和運行 Cloudflare OS 本地開發環境。

## 為什麼有這個腳本

官方的 `cloudflare-os` 快速啟動假設你已經有可用的 `.env.local` 和所有依賴安裝完成。這個腳本自動化設置過程，並修補開發服務器以支持 LAN 訪問（官方已移除的功能）。

## 功能

- 自動安裝 pnpm（如果未安裝）
- 檢查 Node.js 版本（需要 v20+）
- 克隆或更新 cloudflare-os 倉庫
- 安裝所有依賴
- 創建默認 `.env.local` 文件
- 支持本地網絡（LAN）訪問

## 使用方式

### 基本使用（localhost 模式）

```bash
curl -fsSL https://raw.githubusercontent.com/anomixer/cloudflare-os-setup/main/cloudflare-os-setup.sh | bash
```

或者下載腳本後執行：

```bash
chmod +x cloudflare-os-setup.sh
./cloudflare-os-setup.sh
```

### LAN 模式（允許其他設備訪問）

```bash
./cloudflare-os-setup.sh --lan
```

這會將服務綁定到 `0.0.0.0` 而不是 `127.0.0.1`，讓同一網絡中的其他設備可以通過你的 LAN IP 訪問。

**注意：** 官方 cloudflare-os 已移除 `--lan` flag，此腳本使用 `wrangler dev --address 0.0.0.0` 實現 LAN 訪問。

## 系統要求

- Node.js 20 或更高版本
- Linux/macOS（需要 bash）
- 網絡連接（用於克隆倉庫和安裝依賴）

## 腳本流程

1. 檢查並安裝 pnpm
2. 驗證 Node.js 版本
3. 克隆/更新 cloudflare-os 倉庫
4. 安裝 npm 依賴
5. 創建 `.env.local` 配置文件
6. 啟動開發服務器

## 注意事項

- 首次運行會克隆整個 cloudflare-os 倉庫，可能需要一些時間
- 使用 `--lan` 選項時，請確保防火牆允許 8787 端口的入站連接
- 生產環境建議使用 Cloudflare Tunnel 或其他安全方式暴露服務
- 官方默認只綁定 `127.0.0.1` 是出於安全考慮

## 替代方案

### 使用 Cloudflare Tunnel（官方推薦）

對於生產環境或遠程訪問，建議使用 Cloudflare Zero Trust 的 Private Network 功能：

```bash
# 安裝 cloudflared
docker run -d \
  --name cloudflared \
  --network host \
  -v ~/.cloudflared:/etc/cloudflared \
  cloudflare/cloudflared:latest \
  tunnel run
```

### 使用反向代理

```nginx
server {
    listen 80;
    server_name your-lan-ip;
    
    location / {
        proxy_pass http://127.0.0.1:8787;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
    }
}
```

## 原始項目

- [cloudflare/cloudflare-os](https://github.com/cloudflare/cloudflare-os)
- [Issue #86: LAN access discussion](https://github.com/cloudflare/cloudflare-os/issues/86)

## License

MIT
