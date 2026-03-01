# Hisabi Deployment: Docker vs LXC Comparison

## Quick Comparison

| Aspect | Docker | LXC (Ultra-Lightweight) |
|--------|--------|-------------------------|
| **RAM Usage** | 2-4 GB | 512MB - 1GB |
| **Disk Usage** | 20-30 GB | 8-12 GB |
| **Startup Time** | 30-60s | 5-10s |
| **Overhead** | High (containers in VM) | Low (native containers) |
| **Complexity** | Medium | Low |
| **Proxmox Native** | No (needs VM or LXC) | Yes (native) |
| **MySQL** | Required | Optional (SQLite) |

## Docker Approach

### Pros
- ✅ Isolated environments
- ✅ Easy scaling (compose up/down)
- ✅ Portability
- ✅ Built-in health checks

### Cons
- ❌ Higher resource usage
- ❌ Nested containers (if in LXC)
- ❌ More complex networking
- ❌ Requires Docker daemon

### Resource Usage
```
Docker Stack:
  - App Container: ~512MB
  - MySQL Container: ~512MB
  - Redis Container: ~128MB
  - Overhead: ~256MB
  Total: ~1.4GB RAM
```

## LXC Native Approach (Recommended)

### Pros
- ✅ Native to Proxmox
- ✅ Ultra-low overhead
- ✅ Faster startup
- ✅ Direct hardware access
- ✅ Simpler networking
- ✅ Can use SQLite (no MySQL needed)

### Cons
- ❌ Less isolation than Docker
- ❌ Manual dependency management
- ❌ No built-in orchestration

### Resource Usage
```
Native LXC:
  - Nginx: ~50MB
  - PHP-FPM: ~128MB
  - Redis: ~64MB
  - SQLite: ~0MB (file-based)
  - OS overhead: ~256MB
  Total: ~500MB RAM
```

## When to Use Which?

### Use Docker if:
- You need complex multi-service orchestration
- You want easy horizontal scaling
- You're deploying across multiple environments
- You need container isolation

### Use LXC if:
- You want maximum performance on Proxmox
- You have limited resources (RAM/disk)
- You prefer simplicity
- You're running on a single Proxmox node

## Recommended: LXC Ultra-Lightweight

For Hisabi on Proxmox, we recommend the **LXC Ultra-Lightweight** approach:

### Stack
- **OS**: Debian 12 (minimal)
- **Web Server**: Nginx (lighter than Apache)
- **PHP**: 8.2-FPM (FastCGI)
- **Database**: SQLite (no MySQL overhead)
- **Cache**: Redis (lightweight)
- **Queue**: Supervisor (systemd)

### Total Footprint
- **RAM**: ~500MB (vs 2-4GB Docker)
- **Disk**: ~10GB (vs 20-30GB Docker)
- **CPU**: 1 core sufficient

### Performance
- **Cold start**: 5-10 seconds
- **Request latency**: ~50ms
- **Concurrent users**: 100+ (on 1GB RAM)

## Deployment Commands

### Option 1: Docker (Full Stack)
```bash
# On Proxmox host, create LXC with Docker
pct create 200 local:vztmpl/ubuntu-22.04-standard_22.04-1_amd64.tar.zst \
  --hostname hisabi-docker \
  --memory 4096 --cores 2 --rootfs 30

# Inside LXC
apt install docker.io docker-compose
./deploy-proxmox.sh
```

### Option 2: LXC Native (Ultra-Lightweight) ⭐
```bash
# On Proxmox host
./proxmox-create-ultra-lxc.sh 201 1024 10

# Done! Hisabi is running on port 80
```

## Migration Path

If you start with LXC and need to scale:

1. **Scale Up**: Increase LXC resources
   ```bash
   pct set 201 --memory 2048 --cores 2
   pct resize 201 rootfs 20G
   ```

2. **Scale Out**: Convert to Docker when you need:
   - Multiple app instances
   - Load balancing
   - Complex service mesh

3. **Hybrid**: Use LXC for app, Docker for services
   ```bash
   # SQLite → MySQL (when needed)
   apt install mysql-server
   ```

## Security Note

LXC provides process-level isolation. For stronger isolation:
- Use unprivileged LXC containers
- Enable AppArmor/SELinux
- Configure Proxmox firewall
- Regular security updates

## Recommendation

**Start with LXC Ultra-Lightweight.** It's:
- 3x more memory efficient
- 2x faster to deploy
- Native to Proxmox
- Easier to manage

Only move to Docker if you need orchestration features.

## Files

- `proxmox-create-ultra-lxc.sh` - Create optimized LXC
- `lxc-ultra-lightweight.sh` - Setup inside LXC
- `docker-compose.prod.yml` - Docker alternative
- `deploy-proxmox.sh` - Docker deployment