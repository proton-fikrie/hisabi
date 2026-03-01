# Hisabi Ultra-Lightweight LXC Deployment

A production-ready, ultra-lightweight deployment solution for Laravel + React applications on Proxmox using LXC containers.

## 🎯 Design Goals

- **Memory Usage**: <512MB RAM total
- **Disk Usage**: <5GB total
- **Technology Stack**: LXC (not Docker), SQLite (not MySQL), Nginx + PHP-FPM
- **Target**: Single-container deployment for small-to-medium applications

## 📁 Directory Structure

```
hisabi-lxc-deploy/
├── scripts/
│   ├── proxmox-create-lxc.sh    # Run on Proxmox host
│   └── guest-setup.sh           # Run inside LXC container
├── configs/
│   ├── php-fpm-pool.conf        # PHP-FPM optimized for low memory
│   ├── php-optimizations.ini    # PHP settings for 512MB system
│   ├── nginx-hisabi.conf        # Nginx Laravel config
│   └── sqlite-optimizations.conf # SQLite performance tuning
├── systemd/
│   ├── hisabi-queue.service     # Queue worker service
│   ├── hisabi-scheduler.service # Scheduler service
│   └── hisabi-scheduler.timer   # Scheduler timer (runs every minute)
└── README.md
```

## 🚀 Quick Start

### Step 1: Create the LXC Container (on Proxmox Host)

```bash
# Clone this repository
git clone <repo-url>
cd hisabi-lxc-deploy

# Make scripts executable
chmod +x scripts/*.sh

# Create the container (customize as needed)
CT_ID=100 CT_HOSTNAME=hisabi CT_IP=dhcp ./scripts/proxmox-create-lxc.sh

# Or with static IP:
CT_ID=100 CT_HOSTNAME=hisabi CT_IP=192.168.1.100/24 CT_GATEWAY=192.168.1.1 ./scripts/proxmox-create-lxc.sh
```

**Environment Variables:**
| Variable | Default | Description |
|----------|---------|-------------|
| `CT_ID` | 100 | Container ID |
| `CT_HOSTNAME` | hisabi | Container hostname |
| `CT_IP` | dhcp | IP address (dhcp or static like 192.168.1.100/24) |
| `CT_GATEWAY` | - | Gateway for static IP |
| `CT_STORAGE` | local-lvm | Storage pool |
| `CT_DISK_SIZE` | 5 | Disk size in GB |
| `CT_MEMORY` | 512 | Memory in MB |
| `CT_CORES` | 2 | CPU cores |

### Step 2: Deploy Your Application

```bash
# Option A: Copy local files
pct push 100 /path/to/your/hisabi /var/www/hisabi

# Option B: Clone from GitHub
git clone https://github.com/yourusername/hisabi.git
pct push 100 ./hisabi /var/www/hisabi

# Or clone directly inside container
pct exec 100 -- git clone https://github.com/yourusername/hisabi.git /tmp/hisabi
pct exec 100 -- cp -r /tmp/hisabi/* /var/www/hisabi/
```

### Step 3: Run Setup Inside Container

```bash
# Enter container
pct enter 100

# Run setup script
cd /var/www/hisabi
bash scripts/guest-setup.sh
```

Or run directly:
```bash
pct exec 100 -- bash /var/www/hisabi/scripts/guest-setup.sh
```

## 🔧 Manual Configuration

### Laravel `.env` Configuration

The setup script automatically configures for SQLite. Key settings:

```env
APP_NAME=Hisabi
APP_ENV=production
APP_DEBUG=false

DB_CONNECTION=sqlite
DB_DATABASE=/var/lib/sqlite/hisabi.sqlite

CACHE_DRIVER=file
QUEUE_CONNECTION=database
SESSION_DRIVER=file

# Reduce logging verbosity
LOG_LEVEL=warning
```

### Database Configuration (`config/database.php`)

Add SQLite optimizations to your database config:

```php
'sqlite' => [
    'driver' => 'sqlite',
    'url' => env('DATABASE_URL'),
    'database' => env('DB_DATABASE', database_path('database.sqlite')),
    'prefix' => '',
    'foreign_key_constraints' => env('DB_FOREIGN_KEYS', true),
    'busy_timeout' => 5000,
    'journal_mode' => 'WAL',
    'synchronous' => 'NORMAL',
],
```

## 📊 Resource Monitoring

```bash
# Check memory usage
pct exec 100 -- free -h

# Check disk usage
pct exec 100 -- df -h
pct exec 100 -- du -sh /var/www/hisabi

# Check service status
pct exec 100 -- systemctl status nginx php8.2-fpm hisabi-queue

# View logs
pct exec 100 -- journalctl -u hisabi-queue -f
pct exec 100 -- tail -f /var/log/hisabi/*.log
```

## 🔒 Security Hardening

This deployment includes multiple security measures:

1. **Unprivileged LXC container** - Root in container is not root on host
2. **AppArmor profile** - Mandatory access control
3. **Device restrictions** - Limited device access via cgroup
4. **PHP hardening** - Disabled dangerous functions
5. **Nginx security headers** - X-Frame-Options, CSP, etc.
6. **Rate limiting** - Built-in protection against abuse
7. **Systemd hardening** - Service isolation and resource limits

### Additional Security Recommendations

```bash
# Set up firewall (inside container)
apt-get install -y ufw
ufw default deny incoming
ufw default allow outgoing
ufw allow 80/tcp
ufw allow 443/tcp
ufw enable

# Set up fail2ban (if needed)
apt-get install -y fail2ban
```

## 📦 Backup Strategy

### Automated Backup Script

```bash
#!/bin/bash
# /usr/local/bin/backup-hisabi.sh

BACKUP_DIR="/backup/hisabi"
DATE=$(date +%Y%m%d_%H%M%S)
mkdir -p "$BACKUP_DIR"

# Checkpoint and backup database
sqlite3 /var/lib/sqlite/hisabi.sqlite ".backup '${BACKUP_DIR}/hisabi_${DATE}.sqlite'"

# Backup application files
tar czf "${BACKUP_DIR}/hisabi_app_${DATE}.tar.gz" -C /var/www hisabi

# Keep only last 7 backups
ls -t ${BACKUP_DIR}/hisabi_*.sqlite | tail -n +8 | xargs rm -f
ls -t ${BACKUP_DIR}/hisabi_app_*.tar.gz | tail -n +8 | xargs rm -f
```

Add to crontab:
```
0 2 * * * /usr/local/bin/backup-hisabi.sh
```

## 🐛 Troubleshooting

### Check Logs

```bash
# System logs
journalctl -xe

# Application logs
tail -f /var/www/hisabi/storage/logs/laravel.log

# PHP-FPM logs
tail -f /var/log/hisabi/php-fpm-error.log

# Nginx logs
tail -f /var/log/nginx/hisabi-error.log
```

### Common Issues

**Permission Denied on SQLite**
```bash
chown www-data:www-data /var/lib/sqlite/hisabi.sqlite
chmod 664 /var/lib/sqlite/hisabi.sqlite
```

**Out of Memory**
- Reduce PHP-FPM `pm.max_children` to 4
- Reduce `memory_limit` to 96M
- Disable unnecessary Laravel services

**Slow Performance**
```bash
# Optimize SQLite
sqlite3 /var/lib/sqlite/hisabi.sqlite "PRAGMA optimize;"

# Clear Laravel caches
sudo -u www-data php artisan optimize:clear
sudo -u www-data php artisan optimize
```

## 📈 Scaling Up

If you need more resources:

```bash
# On Proxmox host - increase resources
pct set 100 --memory 1024 --swap 1024
cpct resize 100 rootfs 10G

# Then update PHP-FPM pool
# Edit /etc/php/8.2/fpm/pool.d/www.conf
# pm.max_children = 16
# pm.start_servers = 4

# Restart services
pct exec 100 -- systemctl restart php8.2-fpm
```

## 🔄 Updates

### Update Application Code

```bash
pct exec 100 -- bash -c "
    cd /var/www/hisabi
    git pull origin main
    sudo -u www-data composer install --no-dev --optimize-autoloader
    sudo -u www-data php artisan migrate --force
    sudo -u www-data php artisan optimize
    sudo -u www-data npm ci && npm run build
    rm -rf node_modules
"
```

### Update System Packages

```bash
pct exec 100 -- bash -c "
    apt-get update
    apt-get upgrade -y
    apt-get autoremove -y
    apt-get clean
"
```

## 📝 License

This deployment solution is provided as-is for your Laravel applications.

## 🤝 Contributing

Feel free to submit issues or PRs to improve this deployment solution.
