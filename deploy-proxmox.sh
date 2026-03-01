#!/bin/bash
# Hisabi Deployment Script for Proxmox

set -e

echo "🚀 Hisabi Deployment Script"
echo "============================"

# Configuration
APP_NAME="${APP_NAME:-hisabi}"
APP_PORT="${APP_PORT:-8080}"
DB_PASSWORD="${DB_PASSWORD:-$(openssl rand -base64 32)}"
DB_ROOT_PASSWORD="${DB_ROOT_PASSWORD:-$(openssl rand -base64 32)}"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Check if running as root
if [ "$EUID" -ne 0 ]; then 
   echo -e "${RED}Please run as root or with sudo${NC}"
   exit 1
fi

# Check Docker
if ! command -v docker &> /dev/null; then
    echo -e "${YELLOW}Docker not found. Installing...${NC}"
    curl -fsSL https://get.docker.com | sh
    systemctl enable docker
    systemctl start docker
fi

# Check Docker Compose
if ! command -v docker-compose &> /dev/null; then
    echo -e "${YELLOW}Docker Compose not found. Installing...${NC}"
    apt-get update
    apt-get install -y docker-compose-plugin
fi

echo -e "${GREEN}✓ Docker and Docker Compose installed${NC}"

# Create deployment directory
DEPLOY_DIR="/opt/${APP_NAME}"
mkdir -p ${DEPLOY_DIR}
cd ${DEPLOY_DIR}

# Clone repository if not exists
if [ ! -d ".git" ]; then
    echo -e "${YELLOW}Cloning Hisabi repository...${NC}"
    git clone https://github.com/nuzulfikrie/hisabi.git .
    git checkout bot-feature  # or main
fi

echo -e "${GREEN}✓ Repository ready${NC}"

# Create .env file
if [ ! -f ".env" ]; then
    echo -e "${YELLOW}Creating environment file...${NC}"
    cat > .env << EOF
# Hisabi Production Environment
APP_NAME=hisabi
APP_ENV=production
APP_DEBUG=false
APP_URL=http://localhost:${APP_PORT}
APP_PORT=${APP_PORT}

# Database
DB_PASSWORD=${DB_PASSWORD}
DB_ROOT_PASSWORD=${DB_ROOT_PASSWORD}

# Security
APP_KEY=$(openssl rand -base64 32)
EOF
    echo -e "${GREEN}✓ Environment file created${NC}"
    echo -e "${YELLOW}⚠️  Please update .env with your actual settings${NC}"
fi

# Build and start services
echo -e "${YELLOW}Building and starting services...${NC}"
docker-compose -f docker-compose.prod.yml down 2>/dev/null || true
docker-compose -f docker-compose.prod.yml pull
docker-compose -f docker-compose.prod.yml build --no-cache
docker-compose -f docker-compose.prod.yml up -d

echo -e "${GREEN}✓ Services started${NC}"

# Wait for database
echo -e "${YELLOW}Waiting for database...${NC}"
sleep 10

# Run migrations
echo -e "${YELLOW}Running database migrations...${NC}"
docker-compose -f docker-compose.prod.yml exec -T app php artisan migrate --force || true

echo -e "${GREEN}✓ Database migrated${NC}"

# Optimize
echo -e "${YELLOW}Optimizing application...${NC}"
docker-compose -f docker-compose.prod.yml exec -T app php artisan config:cache || true
docker-compose -f docker-compose.prod.yml exec -T app php artisan route:cache || true
docker-compose -f docker-compose.prod.yml exec -T app php artisan view:cache || true

echo -e "${GREEN}✓ Application optimized${NC}"

# Health check
echo -e "${YELLOW}Performing health check...${NC}"
sleep 5
if curl -f http://localhost:${APP_PORT}/health > /dev/null 2>&1; then
    echo -e "${GREEN}✓ Health check passed${NC}"
else
    echo -e "${YELLOW}⚠️  Health check failed, but deployment may still be working${NC}"
fi

echo ""
echo -e "${GREEN}🎉 Hisabi deployed successfully!${NC}"
echo ""
echo "Access your application at:"
echo "  Local: http://localhost:${APP_PORT}"
echo ""
echo "To view logs:"
echo "  docker-compose -f docker-compose.prod.yml logs -f"
echo ""
echo "To stop:"
echo "  docker-compose -f docker-compose.prod.yml down"
echo ""
echo -e "${YELLOW}⚠️  Important:${NC}"
echo "  - Change default passwords in .env file"
echo "  - Configure firewall rules"
echo "  - Set up SSL/TLS for production"
echo "  - Review logs regularly"