#!/bin/bash

# Quick fix script for broken nginx configuration

echo "Fixing nginx configuration..."

# Remove all broken symlinks
echo "Removing broken symlinks..."
sudo find /etc/nginx/sites-enabled/ -type l -exec test ! -e {} \; -delete

# List remaining enabled sites
echo "Currently enabled sites:"
ls -la /etc/nginx/sites-enabled/

# Test nginx
echo "Testing nginx configuration..."
if sudo nginx -t; then
    echo "✓ Nginx configuration is valid"

    # Reload nginx
    sudo systemctl reload nginx
    echo "✓ Nginx reloaded successfully"
else
    echo "✗ Nginx still has errors. Showing details:"
    sudo nginx -T 2>&1 | grep -A 5 -B 5 "emerg\|error" || true

    echo ""
    echo "To fix manually:"
    echo "1. Check what's in sites-enabled: ls -la /etc/nginx/sites-enabled/"
    echo "2. Remove problematic configs: sudo rm /etc/nginx/sites-enabled/PROBLEM_SITE"
    echo "3. Test again: sudo nginx -t"
    echo "4. Reload: sudo systemctl reload nginx"
fi