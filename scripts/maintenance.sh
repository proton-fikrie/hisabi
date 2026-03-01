#!/bin/bash
#
# Maintenance script for Hisabi LXC deployment
#

set -euo pipefail

CT_ID="${1:-100}"
ACTION="${2:-status}"

usage() {
    echo "Usage: $0 [ct_id] [action]"
    echo ""
    echo "Actions:"
    echo "  status      - Show container and service status"
    echo "  restart     - Restart all services"
    echo "  logs        - View application logs"
    echo "  update      - Update system packages"
    echo "  backup      - Create database and file backup"
    echo "  optimize    - Run Laravel optimization commands"
    echo "  shell       - Enter container shell"
    echo ""
    echo "Examples:"
    echo "  $0 100 status"
    echo "  $0 100 backup"
    exit 1
}

if [ $# -lt 1 ]; then
    usage
fi

case "$ACTION" in
    status)
        echo "=== Container Status ==="
        pct status "$CT_ID"
        echo ""
        echo "=== Resource Usage ==="
        pct exec "$CT_ID" -- free -h
        echo ""
        pct exec "$CT_ID" -- df -h
        echo ""
        echo "=== Service Status ==="
        pct exec "$CT_ID" -- systemctl is-active nginx php8.2-fpm hisabi-queue hisabi-scheduler.timer
        echo ""
        echo "=== Memory Details ==="
        pct exec "$CT_ID" -- cat /proc/meminfo | grep -E "(MemTotal|MemFree|MemAvailable|Buffers|Cached)"
        ;;

    restart)
        echo "Restarting services..."
        pct exec "$CT_ID" -- systemctl restart nginx php8.2-fpm hisabi-queue hisabi-scheduler.timer
        echo "Services restarted."
        pct exec "$CT_ID" -- systemctl is-active nginx php8.2-fpm hisabi-queue hisabi-scheduler.timer
        ;;

    logs)
        echo "=== Nginx Error Log ==="
        pct exec "$CT_ID" -- tail -n 20 /var/log/nginx/hisabi-error.log 2>/dev/null || echo "No nginx errors"
        echo ""
        echo "=== PHP-FPM Error Log ==="
        pct exec "$CT_ID" -- tail -n 20 /var/log/hisabi/php-fpm-error.log 2>/dev/null || echo "No PHP-FPM errors"
        echo ""
        echo "=== Queue Worker Log ==="
        pct exec "$CT_ID" -- journalctl -u hisabi-queue -n 20 --no-pager 2>/dev/null || echo "No queue logs"
        echo ""
        echo "=== Laravel Log ==="
        pct exec "$CT_ID" -- tail -n 20 /var/www/hisabi/storage/logs/laravel.log 2>/dev/null || echo "No Laravel logs"
        ;;

    update)
        echo "Updating system packages..."
        pct exec "$CT_ID" -- bash -c "
            export DEBIAN_FRONTEND=noninteractive
            apt-get update
            apt-get upgrade -y
            apt-get autoremove -y
            apt-get clean
        "
        echo "Update complete."
        ;;

    backup)
        BACKUP_DATE=$(date +%Y%m%d_%H%M%S)
        BACKUP_DIR="/var/backups/hisabi"
        echo "Creating backup: $BACKUP_DATE"
        
        pct exec "$CT_ID" -- bash -c "
            mkdir -p $BACKUP_DIR
            
            # Backup database
            sqlite3 /var/lib/sqlite/hisabi.sqlite '.backup $BACKUP_DIR/hisabi_${BACKUP_DATE}.sqlite'
            
            # Backup application files
            tar czf $BACKUP_DIR/hisabi_app_${BACKUP_DATE}.tar.gz -C /var/www hisabi
            
            # Clean old backups (keep 7)
            ls -t $BACKUP_DIR/hisabi_*.sqlite 2>/dev/null | tail -n +8 | xargs rm -f 2>/dev/null || true
            ls -t $BACKUP_DIR/hisabi_app_*.tar.gz 2>/dev/null | tail -n +8 | xargs rm -f 2>/dev/null || true
            
            echo 'Backups in $BACKUP_DIR:'
            ls -lh $BACKUP_DIR/
        "
        ;;

    optimize)
        echo "Running Laravel optimizations..."
        pct exec "$CT_ID" -- bash -c "
            cd /var/www/hisabi
            sudo -u www-data php artisan config:cache
            sudo -u www-data php artisan route:cache
            sudo -u www-data php artisan view:cache
            sudo -u www-data php artisan optimize
            
            # Optimize SQLite
            sqlite3 /var/lib/sqlite/hisabi.sqlite 'PRAGMA optimize;'
            sqlite3 /var/lib/sqlite/hisabi.sqlite 'PRAGMA incremental_vacuum;'
            
            echo 'Optimization complete.'
        "
        ;;

    shell)
        echo "Entering container $CT_ID..."
        pct enter "$CT_ID"
        ;;

    *)
        usage
        ;;
esac
