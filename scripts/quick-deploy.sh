#!/bin/bash
#
# Quick Deploy Script - One-command deployment
# Usage: ./quick-deploy.sh [ct_id] [git_url]
#

set -euo pipefail

CT_ID="${1:-100}"
GIT_URL="${2:-}"
APP_DIR="/var/www/hisabi"

echo "========================================"
echo "Hisabi Quick Deploy"
echo "========================================"
echo ""

# Check if running on Proxmox
if ! command -v pct &> /dev/null; then
    echo "ERROR: This script must run on a Proxmox host"
    exit 1
fi

# Check if container exists
if ! pct list | grep -q "^$CT_ID "; then
    echo "Container $CT_ID does not exist. Creating..."
    ./scripts/proxmox-create-lxc.sh
fi

# Start container if not running
if ! pct status "$CT_ID" | grep -q "status: running"; then
    echo "Starting container $CT_ID..."
    pct start "$CT_ID"
    sleep 3
fi

# Deploy code
echo ""
echo "Deploying application code..."

if [ -n "$GIT_URL" ]; then
    echo "Cloning from: $GIT_URL"
    pct exec "$CT_ID" -- bash -c "
        rm -rf /tmp/hisabi-deploy
        git clone '$GIT_URL' /tmp/hisabi-deploy
        rsync -av --delete /tmp/hisabi-deploy/ $APP_DIR/
        rm -rf /tmp/hisabi-deploy
    "
else
    echo "Using local directory..."
    if [ -d "../hisabi" ]; then
        echo "Found ../hisabi, copying..."
        pct push "$CT_ID" ../hisabi "$APP_DIR"
    elif [ -d "./hisabi" ]; then
        echo "Found ./hisabi, copying..."
        pct push "$CT_ID" ./hisabi "$APP_DIR"
    else
        echo "ERROR: No Hisabi code found. Please provide git URL or place code in ../hisabi"
        exit 1
    fi
fi

# Run setup
echo ""
echo "Running setup inside container..."
pct exec "$CT_ID" -- bash "$APP_DIR/scripts/guest-setup.sh"

echo ""
echo "========================================"
echo "✅ Deployment Complete!"
echo "========================================"
echo ""

# Get container IP
IP=$(pct exec "$CT_ID" -- hostname -I | awk '{print $1}')
echo "Access your application at: http://$IP"
echo ""
echo "Container Info:"
pct list | grep "^$CT_ID "
