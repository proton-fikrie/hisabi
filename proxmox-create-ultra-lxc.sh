#!/bin/bash
# Proxmox Host Script - Create Ultra-Lightweight LXC for Hisabi
# Run this ON the Proxmox host

set -e

CTID="${1:-201}"
CTNAME="hisabi-lxc"
MEMORY="${2:-1024}"  # 1GB RAM (ultra-lightweight)
DISK="${3:-10}"     # 10GB disk
IP="${4:-dhcp}"

echo "🚀 Creating Ultra-Lightweight LXC for Hisabi"
echo "=============================================="
echo "Container ID: $CTID"
echo "Memory: ${MEMORY}MB"
echo "Disk: ${DISK}GB"
echo "IP: $IP"
echo ""

# Check if CTID exists
if pct status $CTID > /dev/null 2>&1; then
    echo "❌ Container $CTID already exists!"
    exit 1
fi

# Download Debian template (lighter than Ubuntu)
TEMPLATE="debian-12-standard_12.7-1_amd64.tar.zst"
if [ ! -f "/var/lib/vz/template/cache/$TEMPLATE" ]; then
    echo "📥 Downloading Debian 12 template..."
    pveam download local $TEMPLATE
fi

# Create ultra-lightweight container
echo "🔧 Creating LXC container..."
pct create $CTID local:vztmpl/$TEMPLATE \
    --hostname $CTNAME \
    --cores 1 \
    --memory $MEMORY \
    --swap 512 \
    --storage local-lvm \
    --rootfs ${DISK} \
    --net0 name=eth0,bridge=vmbr0,ip=$IP \
    --features nesting=1,keyctl=1 \
    --unprivileged 0 \
    --onboot 1

# Optimize container settings for web app
echo "⚡ Optimizing container settings..."
pct set $CTID \
    --mp0 /opt/hisabi,mp=/var/www/hisabi,replicate=0 \
    --startup order=2,up=60,down=60

# Start container
echo "▶️  Starting container..."
pct start $CTID

# Wait for container
echo "⏳ Waiting for container to be ready..."
sleep 15

# Install Hisabi inside container
echo "📦 Installing Hisabi..."
pct exec $CTID -- bash -c "
    # Install prerequisites
    apt update
    apt install -y curl git
    
    # Download setup script
    mkdir -p /opt
    cd /opt
    curl -O https://raw.githubusercontent.com/nuzulfikrie/hisabi/bot-feature/lxc-ultra-lightweight.sh
    chmod +x lxc-ultra-lightweight.sh
    
    # Run setup
    ./lxc-ultra-lightweight.sh
"

# Get container IP
CTIP=$(pct exec $CTID -- hostname -I | awk '{print $1}')

echo ""
echo -e "\033[0;32m✅ Ultra-Lightweight LXC Created!\033[0m"
echo "=================================="
echo "Container ID: $CTID"
echo "Hostname: $CTNAME"
echo "IP Address: $CTIP"
echo "Memory: ${MEMORY}MB"
echo "Disk: ${DISK}GB"
echo ""
echo "Access Hisabi:"
echo "  http://$CTIP"
echo ""
echo "Resource Usage:"
pct status $CTID

# Optional: Setup auto-backup
echo ""
echo "💡 Optional: Add to backup schedule"
echo "  vzdump $CTID --compress zstd --mode stop"

# Optional: Setup firewall
echo ""
echo "💡 Optional: Configure Proxmox firewall"
echo "  - Go to Datacenter → Firewall → Add rule"
echo "  - Allow port 80 from your IP"

# Show upgrade path
echo ""
echo "📈 Upgrade path if you need more resources:"
echo "  pct set $CTID --memory 2048 --cores 2"
echo "  pct resize $CTID rootfs 20G"