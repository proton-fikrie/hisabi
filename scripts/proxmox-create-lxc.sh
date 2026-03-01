#!/bin/bash
#
# Hisabi LXC Container Creation Script for Proxmox
# Ultra-lightweight Laravel + React deployment
# Memory target: <512MB | Disk target: <5GB
#

set -euo pipefail

# Configuration
CT_ID="${CT_ID:-100}"
CT_HOSTNAME="${CT_HOSTNAME:-hisabi}"
CT_IP="${CT_IP:-dhcp}"
CT_GATEWAY="${CT_GATEWAY:-}"
CT_STORAGE="${CT_STORAGE:-local-lvm}"
CT_DISK_SIZE="${CT_DISK_SIZE:-5}"
CT_MEMORY="${CT_MEMORY:-512}"
CT_SWAP="${CT_SWAP:-512}"
CT_CORES="${CT_CORES:-2}"
CT_BRIDGE="${CT_BRIDGE:-vmbr0}"

# Base image - Debian 12 (Bookworm) - lightweight and stable
TEMPLATE="debian-12-standard_12.7-1_amd64.tar.zst"
TEMPLATE_PATH="/var/lib/vz/template/cache/${TEMPLATE}"

echo "========================================"
echo "Hisabi Ultra-Lightweight LXC Deployer"
echo "========================================"
echo ""
echo "Configuration:"
echo "  CT ID:        $CT_ID"
echo "  Hostname:     $CT_HOSTNAME"
echo "  IP:           $CT_IP"
echo "  Disk:         ${CT_DISK_SIZE}GB"
echo "  Memory:       ${CT_MEMORY}MB"
echo "  Cores:        $CT_CORES"
echo "  Storage:      $CT_STORAGE"
echo ""

# Check if running on Proxmox
if ! command -v pct &> /dev/null; then
    echo "ERROR: This script must run on a Proxmox host"
    exit 1
fi

# Download template if not exists
if [ ! -f "$TEMPLATE_PATH" ]; then
    echo "[1/7] Downloading Debian 12 template..."
    pveam update
    pveam download local debian-12-standard_12.7-1_amd64.tar.zst || {
        echo "Trying alternative download method..."
        wget -O "$TEMPLATE_PATH" "http://download.proxmox.com/images/system/${TEMPLATE}" || \
        wget -O "$TEMPLATE_PATH" "https://mirror.turnkeylinux.org/proxmox/images/system/${TEMPLATE}"
    }
else
    echo "[1/7] Template already exists, skipping download"
fi

# Destroy existing container if exists
if pct list | grep -q "^$CT_ID "; then
    echo "[WARNING] Container $CT_ID exists, destroying..."
    pct stop "$CT_ID" 2>/dev/null || true
    pct destroy "$CT_ID"
fi

echo "[2/7] Creating LXC container..."

# Build network config
if [ "$CT_IP" = "dhcp" ]; then
    NET_CONFIG="name=eth0,bridge=$CT_BRIDGE,ip=dhcp"
else
    if [ -n "$CT_GATEWAY" ]; then
        NET_CONFIG="name=eth0,bridge=$CT_BRIDGE,ip=$CT_IP,gw=$CT_GATEWAY"
    else
        NET_CONFIG="name=eth0,bridge=$CT_BRIDGE,ip=$CT_IP"
    fi
fi

# Create container with optimized settings
pct create "$CT_ID" "$TEMPLATE_PATH" \
    --hostname "$CT_HOSTNAME" \
    --storage "$CT_STORAGE" \
    --rootfs "${CT_STORAGE}:${CT_DISK_SIZE}" \
    --memory "$CT_MEMORY" \
    --swap "$CT_SWAP" \
    --cores "$CT_CORES" \
    --net0 "$NET_CONFIG" \
    --features nesting=1,keyctl=1 \
    --onboot 1 \
    --start 1 \
    --ostype debian \
    --unprivileged 1 \
    --timezone host

echo "[3/7] Configuring container for ultra-low memory usage..."

# Optimize container settings for minimal memory
cat >> /etc/pve/lxc/${CT_ID}.conf << 'EOF'

# Memory optimization
lxc.cgroup2.memory.max = 512M
lxc.cgroup2.memory.swap.max = 512M
lxc.cgroup2.memory.high = 450M

# Kernel tweaks for container
lxc.sysctl.vm.swappiness = 10
lxc.sysctl.vm.vfs_cache_pressure = 50
lxc.sysctl.vm.dirty_ratio = 15
lxc.sysctl.vm.dirty_background_ratio = 5

# Limit processes
lxc.cgroup2.pids.max = 500

# Security hardening
lxc.apparmor.profile = generated
lxc.cgroup2.devices.deny = a
lxc.cgroup2.devices.allow = c 1:3 rwm
lxc.cgroup2.devices.allow = c 1:5 rwm
lxc.cgroup2.devices.allow = c 1:8 rwm
lxc.cgroup2.devices.allow = c 1:9 rwm
lxc.cgroup2.devices.allow = c 5:0 rwm
lxc.cgroup2.devices.allow = c 5:1 rwm
lxc.cgroup2.devices.allow = c 136:* rwm
lxc.cgroup2.devices.allow = c 10:229 rwm
EOF

echo "[4/7] Installing prerequisites in container..."

# Wait for container to be ready
sleep 3
pct exec "$CT_ID" -- bash -c "
    export DEBIAN_FRONTEND=noninteractive
    apt-get update
    apt-get install -y --no-install-recommends \
        curl wget ca-certificates gnupg2 apt-transport-https \
        software-properties-common git unzip
    
    # Add PHP 8.2 repository
    curl -fsSL https://packages.sury.org/php/apt.gpg | gpg --dearmor -o /usr/share/keyrings/php.gpg
    echo 'deb [signed-by=/usr/share/keyrings/php.gpg] https://packages.sury.org/php/ bookworm main' > /etc/apt/sources.list.d/php.list
    apt-get update
"

echo "[5/7] Installing PHP 8.2, Nginx, and SQLite..."

pct exec "$CT_ID" -- bash -c "
    export DEBIAN_FRONTEND=noninteractive
    
    # Install minimal PHP 8.2 stack
    apt-get install -y --no-install-recommends \
        php8.2-fpm php8.2-cli php8.2-sqlite3 php8.2-mbstring \
        php8.2-xml php8.2-curl php8.2-zip php8.2-bcmath \
        php8.2-tokenizer php8.2-fileinfo php8.2-openssl \
        php8.2-json php8.2-ctype php8.2-session php8.2-pdo
    
    # Install Nginx (lightweight)
    apt-get install -y --no-install-recommends nginx-light
    
    # Install SQLite and tools
    apt-get install -y --no-install-recommends sqlite3
    
    # Install Composer
    curl -sS https://getcomposer.org/installer | php -- --install-dir=/usr/local/bin --filename=composer
    
    # Install Node.js 20 (for React build)
    curl -fsSL https://deb.nodesource.com/setup_20.x | bash -
    apt-get install -y --no-install-recommends nodejs
    
    # Clean up to save space
    apt-get autoremove -y
    apt-get clean
    rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*
"

echo "[6/7] Setting up Hisabi application directory..."

pct exec "$CT_ID" -- bash -c "
    # Create application directory
    mkdir -p /var/www/hisabi
    chown -R www-data:www-data /var/www/hisabi
    
    # Create SQLite directory
    mkdir -p /var/lib/sqlite
    chown www-data:www-data /var/lib/sqlite
    chmod 750 /var/lib/sqlite
    
    # Set up log directories
    mkdir -p /var/log/hisabi
    chown www-data:www-data /var/log/hisabi
"

echo "[7/7] Configuring system for low memory..."

# Push optimized configs to container
CONFIG_DIR="$(dirname "$0")/../configs"

# PHP-FPM config
pct push "$CT_ID" "${CONFIG_DIR}/php-fpm-pool.conf" /etc/php/8.2/fpm/pool.d/www.conf

# PHP ini optimizations
pct push "$CT_ID" "${CONFIG_DIR}/php-optimizations.ini" /etc/php/8.2/fpm/conf.d/99-optimizations.ini
ln -sf /etc/php/8.2/fpm/conf.d/99-optimizations.ini /etc/php/8.2/cli/conf.d/99-optimizations.ini

# Nginx config
pct push "$CT_ID" "${CONFIG_DIR}/nginx-hisabi.conf" /etc/nginx/sites-available/hisabi
pct exec "$CT_ID" -- ln -sf /etc/nginx/sites-available/hisabi /etc/nginx/sites-enabled/hisabi
pct exec "$CT_ID" -- rm -f /etc/nginx/sites-enabled/default

# Systemd services
SYSTEMD_DIR="$(dirname "$0")/../systemd"
pct push "$CT_ID" "${SYSTEMD_DIR}/hisabi-queue.service" /etc/systemd/system/hisabi-queue.service
pct push "$CT_ID" "${SYSTEMD_DIR}/hisabi-scheduler.service" /etc/systemd/system/hisabi-scheduler.service
pct push "$CT_ID" "${SYSTEMD_DIR}/hisabi-scheduler.timer" /etc/systemd/system/hisabi-scheduler.timer

pct exec "$CT_ID" -- systemctl daemon-reload
pct exec "$CT_ID" -- systemctl enable php8.2-fpm nginx hisabi-queue hisabi-scheduler.timer

# Restart services
pct exec "$CT_ID" -- systemctl restart php8.2-fpm
pct exec "$CT_ID" -- systemctl restart nginx

echo ""
echo "========================================"
echo "✅ Hisabi LXC Container Created!"
echo "========================================"
echo ""
echo "Container Details:"
echo "  ID:           $CT_ID"
echo "  Hostname:     $CT_HOSTNAME"
pct list | grep "^$CT_ID "
echo ""
echo "Next Steps:"
echo "  1. Copy your Hisabi application to the container:"
echo "     pct push $CT_ID /path/to/hisabi /var/www/hisabi"
echo ""
echo "  2. Or clone from git:"
echo "     pct exec $CT_ID -- bash -c 'cd /var/www/hisabi && git clone YOUR_REPO .'"
echo ""
echo "  3. Run the guest setup script inside the container:"
echo "     pct exec $CT_ID -- /var/www/hisabi/scripts/guest-setup.sh"
echo ""
echo "  4. Access the container:"
echo "     pct enter $CT_ID"
echo ""
echo "Memory Usage Estimate: ~350-450MB at idle"
echo "Disk Usage Estimate: ~2-3GB base + app code"
echo ""
