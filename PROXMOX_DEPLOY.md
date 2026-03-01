# Hisabi Deployment Guide for Proxmox

## Overview
Deploy Hisabi (Laravel + React financial app) as a Docker container on Proxmox.

## Architecture
```
┌─────────────────────────────────────────┐
│         Proxmox Node                    │
│  ┌─────────────────────────────────┐   │
│  │     LXC Container (Ubuntu)      │   │
│  │  ┌───────────────────────────┐  │   │
│  │  │   Docker Compose Stack    │  │   │
│  │  │  ┌─────┐ ┌─────┐ ┌────┐  │  │   │
│  │  │  │ App │ │ MySQL│ │Redis│  │  │   │
│  │  │  └──┬──┘ └─────┘ └────┘  │  │   │
│  │  │     │ (Port 8080)         │  │   │
│  │  └─────┼─────────────────────┘  │   │
│  └────────┼─────────────────────────┘   │
└───────────┼─────────────────────────────┘
            │
       Proxmox Firewall/NAT
            │
    External Access (Port 80/443)
```

## Method 1: Quick Deploy (Recommended)

### Step 1: Create LXC Container in Proxmox

```bash
# On Proxmox host
pct create 200 local:vztmpl/ubuntu-22.04-standard_22.04-1_amd64.tar.zst \
  --hostname hisabi-app \
  --cores 2 \
  --memory 2048 \
  --swap 512 \
  --storage local-lvm \
  --rootfs 20 \
  --net0 name=eth0,bridge=vmbr0,ip=dhcp \
  --features nesting=1,keyctl=1

pct start 200
pct exec 200 -- bash
```

### Step 2: Inside LXC Container

```bash
# Install prerequisites
apt update && apt install -y curl git

# Create deploy directory
mkdir -p /opt/hisabi && cd /opt/hisabi

# Download deployment script
curl -O https://raw.githubusercontent.com/nuzulfikrie/hisabi/bot-feature/deploy-proxmox.sh
chmod +x deploy-proxmox.sh

# Run deployment
./deploy-proxmox.sh
```

### Step 3: Configure Proxmox Firewall

```bash
# On Proxmox host
iptables -t nat -A PREROUTING -p tcp --dport 80 -j DNAT --to-destination 192.168.1.200:8080
iptables -t nat -A POSTROUTING -j MASQUERADE
```

Or use Proxmox SDN:
```bash
# In Proxmox Web UI → Datacenter → SDN → Zones → Create
# Then add firewall rules
```

## Method 2: Manual Docker Setup

### Step 1: Prepare Environment

```bash
cd /opt/hisabi

# Create .env file
cat > .env << 'EOF'
APP_NAME=hisabi
APP_ENV=production
APP_DEBUG=false
APP_URL=http://your-domain.com
APP_PORT=8080

# Database (CHANGE THESE!)
DB_PASSWORD=your-secure-password
DB_ROOT_PASSWORD=your-root-password
EOF
```

### Step 2: Deploy

```bash
docker-compose -f docker-compose.prod.yml up -d
```

### Step 3: Initial Setup

```bash
# Run migrations
docker-compose -f docker-compose.prod.yml exec app php artisan migrate --force

# Create admin user
docker-compose -f docker-compose.prod.yml exec app php artisan tinker
# Then: User::create(['name' => 'Admin', 'email' => 'admin@example.com', 'password' => bcrypt('password')])
```

## Post-Deployment

### SSL/TLS with Let's Encrypt

```bash
# Install certbot
docker run -it --rm \
  -v "/etc/letsencrypt:/etc/letsencrypt" \
  -v "/var/lib/letsencrypt:/var/lib/letsencrypt" \
  certbot/certbot certonly --standalone -d your-domain.com

# Update docker-compose to use HTTPS
```

### Backup Strategy

```bash
# Create backup script
cat > /opt/backup-hisabi.sh << 'EOF'
#!/bin/bash
BACKUP_DIR="/backup/hisabi/$(date +%Y%m%d_%H%M%S)"
mkdir -p $BACKUP_DIR

# Backup database
docker exec hisabi-mysql mysqldump -u root -p hisabi > $BACKUP_DIR/db.sql

# Backup storage
tar -czf $BACKUP_DIR/storage.tar.gz /opt/hisabi/storage

# Cleanup old backups (keep 7 days)
find /backup/hisabi -type d -mtime +7 -exec rm -rf {} \;
EOF

chmod +x /opt/backup-hisabi.sh

# Add to cron
echo "0 2 * * * /opt/backup-hisabi.sh" | crontab -
```

### Monitoring

```bash
# Install node-exporter for Prometheus monitoring
docker run -d \
  --name node-exporter \
  --net="host" \
  --pid="host" \
  -v "/:/host:ro,rslave" \
  prom/node-exporter:latest \
  --path.rootfs=/host
```

## Troubleshooting

### Container Won't Start
```bash
# Check logs
docker-compose -f docker-compose.prod.yml logs

# Check disk space
df -h

# Check memory
free -h
```

### Database Connection Issues
```bash
# Verify MySQL is running
docker-compose -f docker-compose.prod.yml ps

# Check MySQL logs
docker-compose -f docker-compose.prod.yml logs mysql

# Reset database (WARNING: Destroys data!)
docker-compose -f docker-compose.prod.yml down -v
docker-compose -f docker-compose.prod.yml up -d
```

### Port Already in Use
```bash
# Find what's using port 8080
netstat -tlnp | grep 8080

# Change port in .env
APP_PORT=8081
```

## Security Checklist

- [ ] Change default database passwords
- [ ] Configure firewall rules
- [ ] Enable SSL/TLS
- [ ] Set up fail2ban
- [ ] Disable root SSH login
- [ ] Set up automated backups
- [ ] Configure log rotation
- [ ] Enable Proxmox firewall

## Resource Requirements

| Component | Minimum | Recommended |
|-----------|---------|-------------|
| CPU | 2 cores | 4 cores |
| RAM | 2 GB | 4 GB |
| Disk | 20 GB | 50 GB |
| Network | 100 Mbps | 1 Gbps |

## Support

- Hisabi Issues: https://github.com/nuzulfikrie/hisabi/issues
- Proxmox Docs: https://pve.proxmox.com/wiki/Main_Page
- Docker Docs: https://docs.docker.com/