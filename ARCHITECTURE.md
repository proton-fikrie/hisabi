# Hisabi LXC Deployment - Architecture Overview

## System Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                        Proxmox Host                              │
│  ┌─────────────────────────────────────────────────────────┐    │
│  │          LXC Container (ID: 100)                         │    │
│  │         < 512MB RAM, 5GB Disk                            │    │
│  │                                                          │    │
│  │   ┌──────────────┐     ┌──────────────┐                 │    │
│  │   │   Nginx      │────▶│  PHP-FPM     │                 │    │
│  │   │  (Reverse    │     │  (8 max      │                 │    │
│  │   │   Proxy)     │     │   children)  │                 │    │
│  │   └──────────────┘     └──────┬───────┘                 │    │
│  │          │                     │                        │    │
│  │          ▼                     ▼                        │    │
│  │   ┌─────────────────────────────────┐                   │    │
│  │   │       Laravel Application       │                   │    │
│  │   │          (Hisabi)               │                   │    │
│  │   │  ┌──────────┐  ┌──────────────┐ │                   │    │
│  │   │  │   API    │  │  React SPA   │ │                   │    │
│  │   │  └──────────┘  └──────────────┘ │                   │    │
│  │   └──────────────┬──────────────────┘                   │    │
│  │                  │                                      │    │
│  │                  ▼                                      │    │
│  │   ┌─────────────────────────────────┐                   │    │
│  │   │   SQLite (WAL mode)             │                   │    │
│  │   │   /var/lib/sqlite/hisabi.sqlite │                   │    │
│  │   └─────────────────────────────────┘                   │    │
│  │                                                          │    │
│  │   ┌──────────────┐  ┌──────────────┐                   │    │
│  │   │ Queue Worker │  │   Scheduler  │                   │    │
│  │   │   (systemd)  │  │   (cron)     │                   │    │
│  │   └──────────────┘  └──────────────┘                   │    │
│  │                                                          │    │
│  └─────────────────────────────────────────────────────────┘    │
│                              │                                   │
│                              │ VMBridge (vmbr0)                  │
└──────────────────────────────┼───────────────────────────────────┘
                               │
                               ▼
                         [Your Network]
```

## Memory Budget Breakdown (512MB Total)

| Component | Memory Allocation |
|-----------|------------------|
| Linux OS + Base | ~80-100MB |
| Nginx | ~20-30MB |
| PHP-FPM (8 workers × 16MB avg) | ~128MB |
| SQLite Cache | ~32MB |
| Laravel Application | ~64MB |
| Queue Worker | ~64MB |
| Buffer / Free | ~80-100MB |
| **Total Target** | **~450-512MB** |

## Disk Usage Breakdown (5GB Total)

| Component | Size |
|-----------|------|
| Base Debian System | ~1.2GB |
| PHP 8.2 + Extensions | ~200MB |
| Nginx | ~50MB |
| Node.js (for build) | ~200MB |
| Application Code | ~100-500MB |
| Composer Dependencies | ~200-400MB |
| SQLite Database | ~50-200MB |
| Logs | ~100MB |
| Build Assets | ~100-300MB |
| **Total Typical** | **~2.5-4GB** |

## Security Layers

```
1. Proxmox Level:
   - Unprivileged container (no host root access)
   - Cgroups resource limits
   - AppArmor mandatory access control

2. Container Level:
   - Minimal base system (Debian minimal)
   - No unnecessary services
   - Firewall (UFW recommended)

3. Application Level:
   - PHP disable_functions
   - Nginx security headers
   - Rate limiting
   - Laravel CSRF protection

4. Service Level:
   - Systemd hardening (ProtectSystem, etc.)
   - Resource limits per service
   - Dedicated user (www-data)
```

## File Locations

| File | Path |
|------|------|
| Application | `/var/www/hisabi` |
| Database | `/var/lib/sqlite/hisabi.sqlite` |
| PHP-FPM Config | `/etc/php/8.2/fpm/pool.d/www.conf` |
| PHP Settings | `/etc/php/8.2/fpm/conf.d/99-optimizations.ini` |
| Nginx Config | `/etc/nginx/sites-available/hisabi` |
| Logs | `/var/log/hisabi/` |
| Systemd Services | `/etc/systemd/system/hisabi-*.service` |

## Service Management

```bash
# Check all services
systemctl status nginx php8.2-fpm hisabi-queue hisabi-scheduler.timer

# Restart services
systemctl restart nginx
systemctl restart php8.2-fpm
systemctl restart hisabi-queue
systemctl restart hisabi-scheduler.timer

# View logs
journalctl -u hisabi-queue -f
tail -f /var/log/hisabi/queue-worker.log
```

## Network Flow

```
Internet → Proxmox Host → LXC Container
                             │
                             ▼
                    ┌────────────────┐
                    │  Nginx :80     │
                    │  - Rate Limit  │
                    │  - Static Cache│
                    └───────┬────────┘
                            │
            ┌───────────────┼───────────────┐
            │               │               │
            ▼               ▼               ▼
      [Static File]  [PHP-FPM]      [Storage]
                          │
                          ▼
                   [Laravel App]
                          │
                          ▼
                   [SQLite DB]
```

## Performance Tuning

### SQLite WAL Mode Benefits:
- Readers don't block writers
- Writers don't block readers
- Faster write performance
- Better crash recovery

### PHP OPcache Settings:
- 64MB shared memory
- 4000 cached files
- Preloading support ready

### Nginx Optimizations:
- Keepalive connections to PHP-FPM
- Static file caching (1 year)
- Gzip compression
- Rate limiting on API/auth

## Backup Strategy

### Automated Daily:
```bash
# SQLite backup (hot backup, no downtime)
sqlite3 /var/lib/sqlite/hisabi.sqlite ".backup '/backup/hisabi_$(date +%Y%m%d).sqlite'"

# File backup
tar czf "/backup/hisabi_app_$(date +%Y%m%d).tar.gz" -C /var/www hisabi
```

### Restore:
```bash
# Stop services
systemctl stop hisabi-queue php8.2-fpm

# Restore database
cp /backup/hisabi_20240101.sqlite /var/lib/sqlite/hisabi.sqlite
chown www-data:www-data /var/lib/sqlite/hisabi.sqlite

# Restore files
tar xzf /backup/hisabi_app_20240101.tar.gz -C /var/www

# Start services
systemctl start php8.2-fpm hisabi-queue
```

## Monitoring Checklist

- [ ] Container CPU usage
- [ ] Memory usage (should stay <450MB)
- [ ] Disk usage (should stay <4GB)
- [ ] Nginx access logs for errors
- [ ] PHP-FPM slow logs
- [ ] Queue worker processing
- [ ] SQLite database integrity (weekly)
- [ ] Backup verification (monthly)
