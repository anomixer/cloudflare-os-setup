#!/usr/bin/env bash
set -e

# Cloudflare OS Setup Script
# Original: https://github.com/cloudflare/cloudflare-os
# Modified: Added --lan option for local network access

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Parse arguments
LAN_MODE=false
for arg in "$@"; do
    case $arg in
        --lan)
            LAN_MODE=true
            shift
            ;;
    esac
done

echo -e "${GREEN}=== Cloudflare OS Setup ===${NC}"

# Check for pnpm
if ! command -v pnpm &> /dev/null; then
    echo -e "${RED}pnpm not found. Installing...${NC}"
    curl -fsSL https://get.pnpm.io/install.sh | sh -
    export PNPM_HOME="$HOME/.local/share/pnpm"
    export PATH="$PNPM_HOME:$PATH"
fi

echo -e "${YELLOW}Checking Node.js version...${NC}"
NODE_VERSION=$(node -v | cut -d'v' -f2 | cut -d'.' -f1)
if [ "$NODE_VERSION" -lt 20 ]; then
    echo -e "${RED}Node.js version must be 20 or higher${NC}"
    exit 1
fi

# Clone or update cloudflare-os
if [ -d "cloudflare-os" ]; then
    echo -e "${YELLOW}cloudflare-os directory exists. Pulling latest changes...${NC}"
    cd cloudflare-os
    git pull
    cd ..
else
    echo -e "${YELLOW}Cloning cloudflare-os repository...${NC}"
    git clone https://github.com/cloudflare/cloudflare-os.git
fi

# Install dependencies
echo -e "${YELLOW}Installing dependencies...${NC}"
cd cloudflare-os
pnpm install

# Create .env.local if not exists
if [ ! -f .env.local ]; then
    echo -e "${YELLOW}Creating .env.local...${NC}"
    cat > .env.local << 'EOF'
# Cloudflare OS Environment Variables
# Edit these values as needed
EOF
fi

echo -e "${GREEN}=== Setup Complete ===${NC}"
echo ""

# Start the development server
if [ "$LAN_MODE" = true ]; then
    echo -e "${GREEN}Starting Cloudflare OS in LAN mode (bound to 0.0.0.0)...${NC}"
    echo -e "${YELLOW}Your LAN IP address:${NC}"
    hostname -I | awk '{print $1}' || ip addr show | grep 'inet ' | grep -v '127.0.0.1' | awk '{print $2}' | cut -d'/' -f1
    echo ""
    echo -e "${YELLOW}Access from other devices using: http://<YOUR_LAN_IP>:8787${NC}"
    echo ""
    
    # Use wrangler dev with 0.0.0.0 binding
    if [ -f "wrangler.toml" ]; then
        pnpm exec wrangler dev --address 0.0.0.0 --port 8787
    elif [ -f "wrangler.json" ]; then
        pnpm exec wrangler dev --address 0.0.0.0 --port 8787
    else
        WRANGLER_CONFIG=$(find . -name "wrangler.toml" -o -name "wrangler.json" | head -1)
        if [ -n "$WRANGLER_CONFIG" ]; then
            pnpm exec wrangler dev --address 0.0.0.0 --port 8787
        else
            echo -e "${RED}No wrangler config found. Using default run-local (localhost only)${NC}"
            pnpm run-local
        fi
    fi
else
    echo -e "${GREEN}Starting Cloudflare OS in localhost mode...${NC}"
    echo -e "${YELLOW}Access at: http://localhost:8787${NC}"
    echo ""
    pnpm run-local
fi
