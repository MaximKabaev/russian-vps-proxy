#!/bin/bash

# Origin Server Configuration Script for Russian VPS Proxy
# This script configures the origin server to accept connections from Russian proxy

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

print_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

# Get user inputs
read -p "Enter your domain name (e.g., lekar-apteka.ru): " DOMAIN
DOMAIN=$(echo "$DOMAIN" | xargs)

if [ -z "$DOMAIN" ]; then
    print_error "Domain cannot be empty"
    exit 1
fi

echo
print_warning "You entered domain: '$DOMAIN'"
read -p "Is this correct? (y/n): " CONFIRM
if [ "$CONFIRM" != "y" ]; then
    print_info "Exiting. Please run the script again with correct domain."
    exit 1
fi

read -p "Enter the Russian VPS IP to whitelist: " PROXY_IP
PROXY_IP=$(echo "$PROXY_IP" | xargs)

# Validate IP
if ! [[ $PROXY_IP =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
    print_error "Invalid IP address format"
    exit 1
fi

read -p "Enter backend port (default 3001): " BACKEND_PORT
BACKEND_PORT=${BACKEND_PORT:-3001}

read -p "Enter frontend port (default 3000): " FRONTEND_PORT
FRONTEND_PORT=${FRONTEND_PORT:-3000}

print_info "Setting up origin server for domain: $DOMAIN"
print_info "Whitelisting Russian VPS: $PROXY_IP"
print_info "Backend port: $BACKEND_PORT, Frontend port: $FRONTEND_PORT"

# Check for existing configuration
if [ -f "/etc/nginx/sites-available/$DOMAIN" ]; then
    print_warning "Configuration for $DOMAIN already exists"
    read -p "Do you want to overwrite it? (y/n): " OVERWRITE
    if [ "$OVERWRITE" != "y" ]; then
        print_info "Creating backup of existing configuration..."
        sudo cp /etc/nginx/sites-available/$DOMAIN /etc/nginx/sites-available/$DOMAIN.backup.$(date +%Y%m%d_%H%M%S)
    fi
fi

# Create nginx configuration
print_info "Creating nginx configuration..."
sudo tee /etc/nginx/sites-available/$DOMAIN > /dev/null <<EOF
server {
    listen 80;
    server_name $DOMAIN;

    if (\$host = $DOMAIN) {
        return 301 https://\$host\$request_uri;
    }

    return 404;
}

server {
    listen 443 ssl;
    server_name $DOMAIN;

    ssl_certificate /etc/letsencrypt/live/$DOMAIN/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/$DOMAIN/privkey.pem;
    include /etc/letsencrypt/options-ssl-nginx.conf;
    ssl_dhparam /etc/letsencrypt/ssl-dhparams.pem;

    # Whitelist Russian proxy only
    allow $PROXY_IP;
    deny all;

    # Health check (open to all)
    location /health {
        allow all;
        proxy_pass http://localhost:$BACKEND_PORT;
    }

    location /api/ {
        proxy_pass http://localhost:$BACKEND_PORT;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection 'upgrade';
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_cache_bypass \$http_upgrade;
        proxy_connect_timeout 30s;
        proxy_send_timeout 30s;
        proxy_read_timeout 30s;
    }

    location /products/ {
        proxy_pass http://localhost:$BACKEND_PORT;
        proxy_http_version 1.1;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_cache_valid 200 1h;
        add_header X-Cache-Status \$upstream_cache_status;
    }

    location / {
        proxy_pass http://localhost:$FRONTEND_PORT;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection 'upgrade';
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_cache_bypass \$http_upgrade;
    }
}
EOF

# Enable the site
print_info "Enabling site configuration..."
sudo ln -sf /etc/nginx/sites-available/$DOMAIN /etc/nginx/sites-enabled/$DOMAIN

# Test nginx configuration
print_info "Testing nginx configuration..."
if sudo nginx -t; then
    print_success "Nginx configuration is valid"

    # Reload nginx
    sudo systemctl reload nginx
    print_success "Nginx reloaded"
else
    print_error "Nginx configuration test failed"
    print_info "Please check the configuration manually"
    exit 1
fi

# Check if SSL certificate exists
if [ ! -f "/etc/letsencrypt/live/$DOMAIN/fullchain.pem" ]; then
    print_warning "SSL certificate not found for $DOMAIN"
    print_info "You need to obtain an SSL certificate. Run:"
    echo "  sudo certbot --nginx -d $DOMAIN"
    echo
fi

# Setup firewall rules (optional)
read -p "Do you want to configure UFW firewall rules? (y/n): " SETUP_FW
if [ "$SETUP_FW" == "y" ]; then
    print_info "Setting up firewall rules..."

    # Allow SSH (don't lock ourselves out)
    sudo ufw allow 22/tcp

    # Allow from Russian VPS only
    sudo ufw allow from $PROXY_IP to any port 80
    sudo ufw allow from $PROXY_IP to any port 443

    # Enable firewall
    sudo ufw --force enable
    print_success "Firewall configured"
fi

print_success "======================================="
print_success "Origin server configuration completed!"
print_success "======================================="
echo
print_info "Configuration summary:"
print_info "  Domain: $DOMAIN"
print_info "  Russian VPS IP (whitelisted): $PROXY_IP"
print_info "  Backend port: $BACKEND_PORT"
print_info "  Frontend port: $FRONTEND_PORT"
echo
print_info "Testing:"
print_info "  From Russian VPS: curl -I https://$DOMAIN"
print_info "  Health check: curl http://localhost/health"
echo
print_warning "IMPORTANT:"
print_warning "  - Only the Russian VPS ($PROXY_IP) can access this server"
print_warning "  - Health endpoint (/health) is open to all for monitoring"
print_warning "  - Make sure your backend is running on port $BACKEND_PORT"
print_warning "  - Make sure your frontend is running on port $FRONTEND_PORT"
echo
print_info "To add more proxy IPs later, edit /etc/nginx/sites-available/$DOMAIN"
print_info "Add more 'allow' lines before 'deny all'"