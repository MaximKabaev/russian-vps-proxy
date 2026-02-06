#!/bin/bash

# Russian VPS Reverse Proxy Setup Script
# This script sets up nginx as a reverse proxy on a Russian VPS

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

# Get user inputs
read -p "Enter your domain name (e.g., lekar-apteka.ru): " DOMAIN
read -p "Enter your origin server domain or IP: " ORIGIN_HOST
read -p "Use HTTPS to connect to origin? (y/n, default y): " USE_HTTPS
USE_HTTPS=${USE_HTTPS:-y}

if [ "$USE_HTTPS" == "y" ]; then
    ORIGIN_URL="https://$ORIGIN_HOST"
else
    ORIGIN_URL="http://$ORIGIN_HOST"
fi

print_info "Setting up reverse proxy: $DOMAIN -> $ORIGIN_URL"
print_info "Your origin nginx will handle /api/ and /products/ routing"

# Update system
print_info "Updating system packages..."
sudo apt-get update
sudo apt-get upgrade -y

# Install nginx and certbot
print_info "Installing nginx and certbot..."
sudo apt-get install -y nginx certbot python3-certbot-nginx

# Create cache directory
sudo mkdir -p /var/cache/nginx
sudo chown www-data:www-data /var/cache/nginx

# Create nginx configuration
print_info "Creating nginx configuration..."
sudo tee /etc/nginx/sites-available/$DOMAIN > /dev/null <<EOF
# Cache configuration
proxy_cache_path /var/cache/nginx levels=1:2 keys_zone=static_cache:10m max_size=1g inactive=7d use_temp_path=off;

# Rate limiting
limit_req_zone \$binary_remote_addr zone=general:10m rate=10r/s;

server {
    listen 80;
    server_name $DOMAIN www.$DOMAIN;

    # Let's Encrypt challenge
    location /.well-known/acme-challenge/ {
        root /var/www/html;
    }

    # Redirect to HTTPS
    location / {
        return 301 https://\$server_name\$request_uri;
    }
}

server {
    listen 443 ssl http2;
    server_name $DOMAIN www.$DOMAIN;

    # SSL certificates (will be added by certbot)
    # ssl_certificate /etc/letsencrypt/live/$DOMAIN/fullchain.pem;
    # ssl_certificate_key /etc/letsencrypt/live/$DOMAIN/privkey.pem;

    # SSL configuration
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers HIGH:!aNULL:!MD5;
    ssl_prefer_server_ciphers off;

    # Security headers
    add_header X-Frame-Options "SAMEORIGIN" always;
    add_header X-Content-Type-Options "nosniff" always;
    add_header X-XSS-Protection "1; mode=block" always;

    # Rate limiting
    limit_req zone=general burst=20 nodelay;

    # Proxy settings
    proxy_http_version 1.1;
    proxy_set_header Upgrade \$http_upgrade;
    proxy_set_header Connection 'upgrade';
    proxy_set_header Host \$host;
    proxy_cache_bypass \$http_upgrade;
    proxy_set_header X-Real-IP \$remote_addr;
    proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
    proxy_set_header X-Forwarded-Proto \$scheme;

    # Timeouts
    proxy_connect_timeout 60s;
    proxy_send_timeout 60s;
    proxy_read_timeout 60s;

    # API routes - no caching, pass to origin server
    # Your origin nginx will route this to localhost:3001
    location /api/ {
        proxy_pass $ORIGIN_URL;
        proxy_no_cache 1;
        proxy_cache_bypass 1;
    }

    # Product images with caching
    # Your origin nginx will route this to localhost:3001
    location /products/ {
        proxy_pass $ORIGIN_URL;
        proxy_cache static_cache;
        proxy_cache_valid 200 7d;
        proxy_cache_valid 404 1h;
        add_header X-Cache-Status \$upstream_cache_status;
        expires 7d;
    }

    # Frontend and static assets
    # Your origin nginx will route this to localhost:3000
    location / {
        proxy_pass $ORIGIN_URL;

        # Cache static assets
        location ~* \.(jpg|jpeg|png|gif|ico|css|js|svg|woff|woff2|ttf|eot)$ {
            proxy_pass $ORIGIN_URL;
            proxy_cache static_cache;
            proxy_cache_valid 200 7d;
            proxy_cache_valid 404 1h;
            proxy_cache_use_stale error timeout updating http_500 http_502 http_503 http_504;
            proxy_cache_background_update on;
            proxy_cache_lock on;
            add_header X-Cache-Status \$upstream_cache_status;
            expires 7d;
            add_header Cache-Control "public, immutable";
        }
    }

    # Health check endpoint (local)
    location /proxy-health {
        access_log off;
        add_header Content-Type text/plain;
        return 200 "Proxy OK";
    }

    # Increase body size for uploads
    client_max_body_size 10M;

    # Gzip compression
    gzip on;
    gzip_vary on;
    gzip_min_length 1024;
    gzip_types text/plain text/css text/xml text/javascript application/javascript application/xml+rss application/json;
}
EOF

# Enable the site
print_info "Enabling site configuration..."
sudo ln -sf /etc/nginx/sites-available/$DOMAIN /etc/nginx/sites-enabled/
sudo rm -f /etc/nginx/sites-enabled/default

# Test nginx configuration
print_info "Testing nginx configuration..."
if sudo nginx -t; then
    print_success "Nginx configuration is valid"
else
    print_error "Nginx configuration test failed"
    exit 1
fi

# Reload nginx
sudo systemctl reload nginx
print_success "Nginx reloaded"

# Setup SSL with Let's Encrypt
print_info "Setting up SSL certificate with Let's Encrypt..."
sudo certbot --nginx -d $DOMAIN -d www.$DOMAIN --non-interactive --agree-tos --email admin@$DOMAIN --redirect

# Setup firewall
print_info "Configuring firewall..."
sudo ufw allow 22/tcp
sudo ufw allow 80/tcp
sudo ufw allow 443/tcp
sudo ufw --force enable

# Create monitoring script
print_info "Creating health check script..."
sudo tee /usr/local/bin/check-origin.sh > /dev/null <<'EOF'
#!/bin/bash
# Check if origin server is accessible
ORIGIN_URL="$1"
if curl -s -o /dev/null -w "%{http_code}" "$ORIGIN_URL" | grep -q "200\|301\|302"; then
    echo "Origin server is UP"
    exit 0
else
    echo "Origin server is DOWN"
    # Could add alerting here
    exit 1
fi
EOF

sudo chmod +x /usr/local/bin/check-origin.sh

# Add cron job for monitoring
print_info "Setting up monitoring cron job..."
(crontab -l 2>/dev/null; echo "*/5 * * * * /usr/local/bin/check-origin.sh $ORIGIN_URL/health >> /var/log/origin-check.log 2>&1") | crontab -

print_success "======================================="
print_success "Russian proxy setup completed!"
print_success "======================================="
echo
print_info "Next steps:"
print_info "1. Update DNS: Point $DOMAIN to this server's IP"
print_info "2. On origin server: Whitelist this server's IP in firewall/nginx"
print_info "3. Test: curl https://$DOMAIN"
print_info "4. Monitor: tail -f /var/log/nginx/access.log"
echo
print_info "Useful commands:"
print_info "  nginx -t              - Test configuration"
print_info "  systemctl status nginx - Check nginx status"
print_info "  tail -f /var/log/nginx/error.log - View errors"
print_info "  du -sh /var/cache/nginx - Check cache size"
echo
print_info "Origin health check:"
print_info "  /usr/local/bin/check-origin.sh $ORIGIN_URL"
echo

print_warning "IMPORTANT: Configure your origin server to accept connections from this VPS!"
print_info "Add this server's IP to your origin nginx or firewall whitelist"