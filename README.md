# Cloudflare OS Setup Script

[中文說明](README.zh-TW.md)

A simple script to quickly setup and run Cloudflare OS local development environment.

## Why this script exists

The official `cloudflare-os` quick-start assumes you already have a working `.env.local` and all dependencies installed. This script automates the setup process and patches the development server to support LAN access (which upstream removed).

## Features

- Automatically installs pnpm (if not installed)
- Checks Node.js version (requires v20+)
- Clones or updates cloudflare-os repository
- Installs all dependencies
- Creates default `.env.local` file
- Supports local network (LAN) access

## Usage

### Basic Usage (localhost mode)

```bash
curl -fsSL https://raw.githubusercontent.com/anomixer/cloudflare-os-setup/main/cloudflare-os-setup.sh | bash
```

Or download and execute the script:

```bash
chmod +x cloudflare-os-setup.sh
./cloudflare-os-setup.sh
```

### LAN Mode (allow other devices to access)

```bash
./cloudflare-os-setup.sh --lan
```

This binds the service to `0.0.0.0` instead of `127.0.0.1`, allowing other devices on the same network to access via your LAN IP.

**Note:** The official cloudflare-os has removed the `--lan` flag. This script uses `wrangler dev --address 0.0.0.0` to implement LAN access.

## Requirements

- Node.js 20 or higher
- Linux/macOS (requires bash)
- Network connection (for cloning repository and installing dependencies)

## Script Flow

1. Check and install pnpm
2. Verify Node.js version
3. Clone/update cloudflare-os repository
4. Install npm dependencies
5. Create `.env.local` configuration file
6. Start development server

## Notes

- First run will clone the entire cloudflare-os repository, which may take some time
- When using `--lan` option, ensure firewall allows inbound connections on port 8787
- For production environments, recommend using Cloudflare Tunnel or other secure methods to expose the service
- Official default binding to `127.0.0.1` is for security reasons

## Alternative Methods

### Using Cloudflare Tunnel (Official Recommendation)

For production or remote access, recommend using Cloudflare Zero Trust Private Network:

```bash
# Install cloudflared
docker run -d \
  --name cloudflared \
  --network host \
  -v ~/.cloudflared:/etc/cloudflared \
  cloudflare/cloudflared:latest \
  tunnel run
```

### Using Reverse Proxy

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

## Original Project

- [cloudflare/cloudflare-os](https://github.com/cloudflare/cloudflare-os)
- [Issue #86: LAN access discussion](https://github.com/cloudflare/cloudflare-os/issues/86)

## License

MIT
