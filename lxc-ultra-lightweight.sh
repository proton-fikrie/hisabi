#!/bin/bash
# Ultra-Lightweight LXC Setup for Hisabi
# Run INSIDE the LXC container (not on Proxmox host)

set -e

echo "🚀 Hisabi Ultra-Lightweight LXC Setup"
echo "======================================"

# Configuration
APP_DIR="/var/www/hisabi"
DB_TYPE="${DB_TYPE:-sqlite}"  # sqlite or mysql
PHP_VERSION="8.2"

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Update system
echo -e "${YELLOW}Updating system...${NC}"
apt update && apt upgrade -y

# Install dependencies (ultra-lightweight stack)
echo -e "${YELLOW}Installing lightweight web stack...${NC}"
apt install -y \
    nginx \
    php${PHP_VERSION}-fpm \
    php${PHP_VERSION}-cli \
    php${PHP_VERSION}-sqlite3 \
    php${PHP_VERSION}-mbstring \
    php${PHP_VERSION}-xml \
    php${PHP_VERSION}-curl \
    php${PHP_VERSION}-zip \
    php${PHP_VERSION}-gd \
    php${PHP_VERSION}-intl \
    composer \
    git \
    curl \
    unzip \
    supervisor

# Install Redis (optional, for caching)
if [ "$DB_TYPE" = "mysql" ]; then
    apt install -y php${PHP_VERSION}-mysql mysql-server redis-server
else
    apt install -y redis-server
fi

echo -e "${GREEN}✓ Packages installed${NC}"

# Create application directory
echo -e "${YELLOW}Setting up application...${NC}"
mkdir -p ${APP_DIR}
cd ${APP_DIR}

# Clone repository
if [ ! -d ".git" ]; then
    git clone https://github.com/nuzulfikrie/hisabi.git .
    git checkout bot-feature 2>/dev/null || git checkout main
fi

# Install PHP dependencies
echo -e "${YELLOW}Installing PHP dependencies...${NC}"
composer install --no-dev --optimize-autoloader --no-interaction

# Create environment file
if [ ! -f ".env" ]; then
    cp .env.prod.example .env
    
    # Generate app key
    php artisan key:generate
    
    # Configure for SQLite (lightweight)
    if [ "$DB_TYPE" = "sqlite" ]; then
        mkdir -p database
touch database/database.sqlite
        sed -i 's/DB_CONNECTION=.*/DB_CONNECTION=sqlite/' .env
        sed -i 's|DB_DATABASE=.*|DB_DATABASE='${APP_DIR}'/database/database.sqlite|' .env
    fi
    
    # Configure Redis
    sed -i 's/CACHE_DRIVER=.*/CACHE_DRIVER=redis/' .env
    sed -i 's/SESSION_DRIVER=.*/SESSION_DRIVER=redis/' .env
    sed -i 's/REDIS_HOST=.*/REDIS_HOST=127.0.0.1/' .env
fi

# Set permissions
chown -R www-data:www-data ${APP_DIR}
chmod -R 755 ${APP_DIR}/storage
chmod -R 755 ${APP_DIR}/bootstrap/cache
if [ "$DB_TYPE" = "sqlite" ]; then
    chmod 666 ${APP_DIR}/database/database.sqlite
fi

echo -e "${GREEN}✓ Application configured${NC}"

# Run migrations
echo -e "${YELLOW}Running database migrations...${NC}"
php artisan migrate --force

# Optimize Laravel
echo -e "${YELLOW}Optimizing application...${NC}"
php artisan config:cache
php artisan route:cache
php artisan view:cache

echo -e "${GREEN}✓ Application optimized${NC}"

# Configure Nginx
echo -e "${YELLOW}Configuring Nginx...${NC}"
cat > /etc/nginx/sites-available/hisabi << 'EOF'
server {
    listen 80;
    server_name _;
    root /var/www/hisabi/public;
    index index.php;

    location / {
        try_files $uri $uri/ /index.php?$query_string;
    }

    location ~ \.php$ {
        include snippets/fastcgi-php.conf;
        fastcgi_pass unix:/run/php/php8.2-fpm.sock;
        fastcgi_param SCRIPT_FILENAME $document_root$fastcgi_script_name;
        include fastcgi_params;
    }

    location ~ /\.(?!well-known).* {
        deny all;
    }

    # Gzip compression
    gzip on;
    gzip_types text/plain text/css application/json application/javascript;
}
EOF

# Enable site
ln -sf /etc/nginx/sites-available/hisabi /etc/nginx/sites-enabled/
rm -f /etc/nginx/sites-enabled/default

# Test Nginx config
nginx -t

echo -e "${GREEN}✓ Nginx configured${NC}"

# Configure PHP-FPM for performance
echo -e "${YELLOW}Tuning PHP-FPM...${NC}"
cat > /etc/php/8.2/fpm/pool.d/www.conf << 'EOF'
[www]
user = www-data
group = www-data
listen = /run/php/php8.2-fpm.sock
listen.owner = www-data
listen.group = www-data
pm = dynamic
pm.max_children = 5
pm.start_servers = 2
pm.min_spare_servers = 1
pm.max_spare_servers = 3
pm.max_requests = 500
EOF

# Configure Supervisor for queue workers
cat > /etc/supervisor/conf.d/hisabi-worker.conf << 'EOF'
[program:hisabi-worker]
process_name=%(program_name)s_%(process_num)02d
command=php /var/www/hisabi/artisan queue:work --sleep=3 --tries=3
autostart=true
autorestart=true
user=www-data
numprocs=1
redirect_stderr=true
stdout_logfile=/var/www/hisabi/storage/logs/worker.log
EOF

# Configure Supervisor for scheduler
cat > /etc/supervisor/conf.d/hisabi-scheduler.conf << 'EOF'
[program:hisabi-scheduler]
process_name=%(program_name)s
command=php /var/www/hisabi/artisan schedule:work
autostart=true
autorestart=true
user=www-data
redirect_stderr=true
stdout_logfile=/var/www/hisabi/storage/logs/scheduler.log
EOF

# Enable and start services
echo -e "${YELLOW}Starting services...${NC}"
systemctl enable nginx
systemctl enable php8.2-fpm
systemctl enable redis-server
systemctl enable supervisor

systemctl restart nginx
systemctl restart php8.2-fpm
systemctl restart redis-server
systemctl restart supervisor

supervisorctl reread
supervisorctl update
supervisorctl start all

echo -e "${GREEN}✓ Services started${NC}"

# Get IP address
IP=$(hostname -I | awk '{print $1}')

echo ""
echo -e "${GREEN}🎉 Hisabi deployed successfully!${NC}"
echo "==================================="
echo "Access your application:"
echo "  http://${IP}"
echo ""
echo "Resources:"
echo "  Memory: $(free -h | grep Mem | awk '{print $3 "/" $2}')"
echo "  Disk: $(df -h / | tail -1 | awk '{print $3 "/" $2}')"
echo ""
echo "Management:"
echo "  Restart Nginx: systemctl restart nginx"
echo "  View logs: tail -f /var/log/nginx/error.log"
echo "  Queue workers: supervisorctl status"
echo ""
echo -e "${YELLOW}⚠️  Remember to:${NC}"
echo "  - Change default passwords"
echo "  - Configure firewall (ufw)"
echo "  - Set up SSL/TLS (certbot)"
echo "  - Enable automatic backups"

# Health check
sleep 2
if curl -f http://localhost/health >/dev/null 2>&1 || curl -f http://localhost >/dev/null 2>&1; then
    echo -e "${GREEN}✓ Health check passed!${NC}"
else
    echo -e "${YELLOW}⚠️  App may still be starting. Check: systemctl status nginx${NC}"
fi