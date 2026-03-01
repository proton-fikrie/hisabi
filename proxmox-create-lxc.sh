#!/bin/bash
# Proxmox LXC Setup Script for Hisabi
# Run this on the Proxmox host

set -e

CTID="${1:-200}"
CTNAME="hisabi-app"
HOSTNAME="${2:-hisabi.local}"
IP="${3:-dhcp}"

echo "🚀 Creating Proxmox LXC Container for Hisabi"
echo "=============================================="
echo "Container ID: $CTID"
echo "Hostname: $HOSTNAME"
echo "IP: $IP"
echo ""

# Check if CTID exists
if pct status $CTID > /dev/null 2>&1; then
    echo "❌ Container $CTID already exists!"
    exit 1
fi

# Download template if not exists
TEMPLATE="ubuntu-22.04-standard_22.04-1_amd64.tar.zst"
if [ ! -f "/var/lib/vz/template/cache/$TEMPLATE" ]; then
    echo "📥 Downloading Ubuntu 22.04 template..."
    pveam download local $TEMPLATE
fi

# Create container
echo "🔧 Creating LXC container..."
pct create $CTID local:vztmpl/$TEMPLATE \
    --hostname $HOSTNAME \
    --cores 2 \
    --memory 2048 \
    --swap 512 \
    --storage local-lvm \
    --rootfs 20 \
    --net0 name=eth0,bridge=vmbr0,ip=$IP \
    --features nesting=1,keyctl=1 \
    --unprivileged 0

# Start container
echo "▶️  Starting container..."
pct start $CTID

# Wait for container to be ready
sleep 10

# Install Docker inside container
echo "🐳 Installing Docker..."
pct exec $CTID -- bash -c "
    apt-get update
    apt-get install -y curl git ca-certificates gnupg
    install -m 0755 -d /etc/apt/keyrings
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
    chmod a+r /etc/apt/keyrings/docker.gpg
    echo 'deb [arch=amd64 signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu jammy stable' > /etc/apt/sources.list.d/docker.list
    apt-get update
    apt-get install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin
    systemctl enable docker
    usermod -aG docker root
"

# Clone Hisabi repository
echo "📂 Cloning Hisabi repository..."
pct exec $CTID -- bash -c "
    mkdir -p /opt/hisabi
    cd /opt/hisabi
    git clone https://github.com/nuzulfikrie/hisabi.git .
    git checkout bot-feature 2>/dev/null || git checkout main
"

# Copy deployment files
echo "📋 Setting up deployment..."
pct exec $CTID -- bash -c "
    cd /opt/hisabi
    chmod +x deploy-proxmox.sh
"

# Get container IP
CTIP=$(pct exec $CTID -- hostname -I | awk '{print $1}')

echo ""
echo "✅ LXC Container Created Successfully!"
echo "======================================"
echo "Container ID: $CTID"
echo "Hostname: $HOSTNAME"
echo "IP Address: $CTIP"
echo ""
echo "Next steps:"
echo "  1. SSH into container: pct exec $CTID -- bash"
echo "  2. Go to app directory: cd /opt/hisabi"
echo "  3. Run deployment: ./deploy-proxmox.sh"
echo "  4. Access app at: http://$CTIP:8080"
echo ""
echo "Or open Proxmox console and run:"
echo "  cd /opt/hisabi && ./deploy-proxmox.sh"
echo ""
echo "🔒 Security Tips:"
echo "  - Change default passwords"
echo "  - Configure Proxmox firewall"
echo "  - Set up SSL/TLS"
echo "  - Enable automatic backups"