#!/bin/bash
#
# Hisabi Guest Setup Script
# Run this inside the LXC container after code deployment
#

set -euo pipefail

APP_DIR="/var/www/hisabi"
LOG_DIR="/var/log/hisabi"
DB_DIR="/var/lib/sqlite"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

cd "$APP_DIR"

echo "========================================"
echo "Hisabi Application Setup"
echo "========================================"
echo ""

# Check if we're in the right directory
if [ ! -f "composer.json" ]; then
    log_error "composer.json not found. Are you in the right directory?"
    exit 1
fi

log_info "Setting up directory permissions..."
mkdir -p storage/{app,framework/{cache,sessions,testing,views},logs}
mkdir -p bootstrap/cache
mkdir -p "$LOG_DIR"
chown -R www-data:www-data "$APP_DIR"
chmod -R 775 storage bootstrap/cache

log_info "Installing PHP dependencies (optimized for low memory)..."

# Install composer dependencies with memory optimization
# Use --no-dev for production, --optimize-autoloader for faster loading
sudo -u www-data COMPOSER_MEMORY_LIMIT=256M composer install \
    --no-interaction \
    --prefer-dist \
    --optimize-autoloader \
    --no-dev 2>&1 | tee "$LOG_DIR/composer-install.log"

log_info "Setting up environment..."

if [ ! -f ".env" ]; then
    if [ -f ".env.example" ]; then
        cp .env.example .env
        log_info "Created .env from .env.example"
    else
        log_warn ".env.example not found, creating minimal .env"
        cat > .env << 'EOF'
APP_NAME=Hisabi
APP_ENV=production
APP_KEY=
APP_DEBUG=false
APP_URL=http://localhost

# SQLite Configuration
DB_CONNECTION=sqlite
DB_DATABASE=/var/lib/sqlite/hisabi.sqlite

# No additional DB settings needed for SQLite

BROADCAST_DRIVER=log
CACHE_DRIVER=file
FILESYSTEM_DISK=local
QUEUE_CONNECTION=database
SESSION_DRIVER=file
SESSION_LIFETIME=120

# Memory-optimized logging
LOG_CHANNEL=daily
LOG_DEPRECATIONS_CHANNEL=null
LOG_LEVEL=warning

# Disable services we don't need
MAIL_MAILER=log

# Optimizations for low memory
PHP_MEMORY_LIMIT=256M
PHP_MAX_EXECUTION_TIME=30
EOF
    fi
fi

# Generate app key
log_info "Generating application key..."
sudo -u www-data php artisan key:generate --force

# Update .env for SQLite
log_info "Configuring for SQLite..."
sed -i 's/DB_CONNECTION=.*/DB_CONNECTION=sqlite/' .env 2>/dev/null || true
sed -i 's|DB_DATABASE=.*|DB_DATABASE=/var/lib/sqlite/hisabi.sqlite|' .env 2>/dev/null || true
sed -i 's/DB_HOST=.*//' .env 2>/dev/null || true
sed -i 's/DB_PORT=.*//' .env 2>/dev/null || true
sed -i 's/DB_USERNAME=.*//' .env 2>/dev/null || true
sed -i 's/DB_PASSWORD=.*//' .env 2>/dev/null || true

# Set production optimizations
sed -i 's/APP_ENV=.*/APP_ENV=production/' .env
sed -i 's/APP_DEBUG=.*/APP_DEBUG=false/' .env
sed -i 's/CACHE_DRIVER=.*/CACHE_DRIVER=file/' .env
sed -i 's/QUEUE_CONNECTION=.*/QUEUE_CONNECTION=database/' .env
sed -i 's/SESSION_DRIVER=.*/SESSION_DRIVER=file/' .env
sed -i 's/LOG_LEVEL=.*/LOG_LEVEL=warning/' .env

log_info "Creating SQLite database..."

# Create and optimize SQLite database
touch "$DB_DIR/hisabi.sqlite"
chown www-data:www-data "$DB_DIR/hisabi.sqlite"
chmod 664 "$DB_DIR/hisabi.sqlite"

# Apply SQLite optimizations
cat > /tmp/sqlite-optimizations.sql << 'EOF'
-- SQLite Performance Optimizations
PRAGMA journal_mode = WAL;
PRAGMA synchronous = NORMAL;
PRAGMA cache_size = -8192;  -- 8MB cache (negative = pages)
PRAGMA temp_store = MEMORY;
PRAGMA mmap_size = 268435456;  -- 256MB memory map
PRAGMA page_size = 4096;
EOF

sudo -u www-data sqlite3 "$DB_DIR/hisabi.sqlite" < /tmp/sqlite-optimizations.sql
rm -f /tmp/sqlite-optimizations.sql

log_info "Running database migrations..."
sudo -u www-data php artisan migrate --force

log_info "Seeding database (if seeders exist)..."
sudo -u www-data php artisan db:seed --force 2>/dev/null || log_warn "No seeders found or seeding failed"

log_info "Caching Laravel configuration..."
sudo -u www-data php artisan config:cache
sudo -u www-data php artisan route:cache
sudo -u www-data php artisan view:cache

log_info "Building React frontend..."

# Check if package.json exists
if [ -f "package.json" ]; then
    # Install Node dependencies
    log_info "Installing Node.js dependencies..."
    npm ci --production=false --silent 2>&1 | tee "$LOG_DIR/npm-install.log"
    
    # Build for production
    log_info "Building production assets..."
    npm run build 2>&1 | tee "$LOG_DIR/npm-build.log"
    
    # Clean up node_modules to save space
    log_info "Cleaning up node_modules to save disk space..."
    rm -rf node_modules
    
    # Clear npm cache
    npm cache clean --force 2>/dev/null || true
else
    log_warn "No package.json found, skipping frontend build"
fi

log_info "Setting final permissions..."
chown -R www-data:www-data "$APP_DIR"
find "$APP_DIR" -type f -exec chmod 644 {} \;
find "$APP_DIR" -type d -exec chmod 755 {} \;
chmod -R 775 "$APP_DIR/storage" "$APP_DIR/bootstrap/cache"
chmod 664 "$DB_DIR/hisabi.sqlite"

log_info "Restarting services..."
systemctl restart php8.2-fpm
systemctl restart nginx
systemctl restart hisabi-queue
systemctl restart hisabi-scheduler.timer

log_info "Running health checks..."

# Check PHP-FPM
curl -s -o /dev/null -w "%{http_code}" http://localhost/up 2>/dev/null | grep -q "200" || {
    log_warn "PHP-FPM health check endpoint not responding (this is OK if you don't have a /up route)"
}

# Check Nginx
if systemctl is-active --quiet nginx; then
    log_info "✓ Nginx is running"
else
    log_error "✗ Nginx is not running"
fi

# Check PHP-FPM
if systemctl is-active --quiet php8.2-fpm; then
    log_info "✓ PHP-FPM is running"
else
    log_error "✗ PHP-FPM is not running"
fi

# Check queue worker
if systemctl is-active --quiet hisabi-queue; then
    log_info "✓ Queue worker is running"
else
    log_warn "✗ Queue worker is not running (will start on next boot)"
fi

echo ""
echo "========================================"
echo "✅ Hisabi Setup Complete!"
echo "========================================"
echo ""
echo "Application Location: $APP_DIR"
echo "Database Location:    $DB_DIR/hisabi.sqlite"
echo "Log Location:         $LOG_DIR"
echo ""
echo "Service Status:"
systemctl status nginx --no-pager -l | grep "Active:"
systemctl status php8.2-fpm --no-pager -l | grep "Active:"
systemctl status hisabi-queue --no-pager -l | grep "Active:" || true
echo ""
echo "Memory Usage:"
free -h | grep -E "(Mem|Swap)"
echo ""
echo "Disk Usage:"
df -h / | tail -1
echo ""
echo "Useful Commands:"
echo "  View logs:      journalctl -u hisabi-queue -f"
echo "  Queue status:   sudo -u www-data php artisan queue:status"
echo "  Clear caches:   sudo -u www-data php artisan optimize:clear"
echo "  Enter console:  sudo -u www-data php artisan t"
echo ""
