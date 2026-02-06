# Russian VPS Reverse Proxy Setup

A simple script to set up Nginx reverse proxy on a Russian VPS to bypass ISP blocks while keeping your actual servers and data outside Russia.

## Why Use This?

Many international websites are blocked by Russian ISPs. Instead of migrating your entire infrastructure to Russia (which involves data localization laws), you can use a small VPS in Russia as a reverse proxy. Russian users connect to the Russian IP, avoiding blocks, while your actual servers remain outside Russia.

## Architecture

```
Russian Users → Russian VPS (Nginx Proxy) → Your Origin Server → Backend/Frontend
      ↓                    ↓                        ↓
  No ISP blocks      Caches static files     Actual app + database
```

## Benefits

- ✅ **Bypass ISP blocks** - Russian users can access your site
- ✅ **No data in Russia** - Avoid Russian data localization laws
- ✅ **Minimal infrastructure** - 1GB RAM VPS is enough
- ✅ **Keep existing setup** - No need to migrate databases or change architecture
- ✅ **Automatic SSL** - Let's Encrypt certificates configured automatically
- ✅ **Smart caching** - Static assets cached on Russian VPS for speed
- ✅ **Easy rollback** - Just update DNS if issues arise

## Requirements

### Russian VPS
- Ubuntu 20.04+ or Debian 10+
- 1GB RAM minimum
- 10GB disk space
- Public IP address
- Root or sudo access

### Origin Server
- Your existing website (can be anywhere)
- Nginx configured to serve your app
- Ability to whitelist Russian VPS IP

## Installation

### 1. On Russian VPS

```bash
# Download the script
wget https://raw.githubusercontent.com/MaximKabaev/russian-vps-proxy/main/setup-russian-proxy.sh

# Make executable
chmod +x setup-russian-proxy.sh

# Run the setup
./setup-russian-proxy.sh
```

### 2. Follow the prompts

```
Enter your domain name (e.g., lekar-apteka.ru): example.com
Enter your origin server domain or IP: origin-server.com
Use HTTPS to connect to origin? (y/n, default y): y
```

### 3. Update DNS

Point your domain to the Russian VPS IP address.

### 4. Secure Origin Server

On your origin server, whitelist only the Russian VPS IP:

```nginx
# In your origin server's nginx config
geo $proxy_allowed {
    default 0;
    YOUR_RUSSIAN_VPS_IP 1;  # Replace with actual IP
}

server {
    if ($proxy_allowed = 0) {
        return 403;
    }

    # Your existing configuration...
}
```

## What the Script Does

1. **Installs Nginx** - Web server for reverse proxy
2. **Configures Reverse Proxy** - Routes all traffic to your origin
3. **Sets up SSL** - Automatic Let's Encrypt certificates via Certbot
4. **Configures Caching** - Caches static assets (images, CSS, JS)
5. **Adds Security** - Rate limiting, security headers
6. **Sets up Monitoring** - Health checks for origin server
7. **Configures Firewall** - Opens only necessary ports

## Configuration Details

### Caching Strategy
- Static assets (images, CSS, JS): Cached for 7 days
- API routes (`/api/*`): Never cached
- Product images (`/products/*`): Cached for 7 days

### SSL Configuration
- Automatic Let's Encrypt certificates
- Auto-renewal configured
- HTTP to HTTPS redirect
- Modern TLS protocols (1.2, 1.3)

### Performance
- Gzip compression enabled
- Connection pooling
- Background cache updates
- Cache locking to prevent stampedes

## Monitoring

### Check Services
```bash
# Nginx status
systemctl status nginx

# View access logs
tail -f /var/log/nginx/access.log

# View error logs
tail -f /var/log/nginx/error.log

# Check cache size
du -sh /var/cache/nginx
```

### Health Checks
```bash
# Check origin connectivity
/usr/local/bin/check-origin.sh https://your-origin.com

# Check proxy health
curl https://your-domain.com/proxy-health

# View monitoring logs
tail -f /var/log/origin-check.log
```

## Troubleshooting

### SSL Certificate Issues
```bash
# Manually renew certificate
sudo certbot renew --nginx

# Test renewal
sudo certbot renew --dry-run
```

### Cache Issues
```bash
# Clear nginx cache
sudo rm -rf /var/cache/nginx/*
sudo systemctl reload nginx
```

### Origin Connection Issues
```bash
# Test origin connectivity
curl -I https://your-origin-server.com

# Check if origin allows Russian VPS
curl -H "X-Forwarded-For: RUSSIAN_VPS_IP" https://origin.com
```

## Cost Comparison

| Solution | VPS Size | Storage | Complexity | Monthly Cost |
|----------|----------|---------|------------|--------------|
| **Reverse Proxy** | 1GB RAM | 10GB | Simple | ~$5 |
| **Full Migration** | 4GB+ RAM | 50GB+ | Complex | ~$40+ |

## Security Considerations

1. **Origin Whitelisting** - Always whitelist only Russian VPS IP on origin
2. **Rate Limiting** - Configured at 10 requests/second per IP
3. **DDoS Protection** - Consider CloudFlare between users and Russian VPS
4. **Regular Updates** - Keep nginx and system packages updated
5. **Monitoring** - Watch logs for suspicious activity

## Advanced Configuration

### Using CloudFlare
```
Users → CloudFlare → Russian VPS → Origin Server
```

Benefits:
- Additional DDoS protection
- Global CDN
- Hide Russian VPS IP

### Multiple Origins

Edit `/etc/nginx/sites-available/your-domain` to add upstream:

```nginx
upstream backend {
    server origin1.com:443;
    server origin2.com:443 backup;
}

server {
    location / {
        proxy_pass https://backend;
        # ... rest of config
    }
}
```

## License

MIT License - See LICENSE file

## Support

For issues or questions, please open an issue on GitHub.

## Author

Created for the Russian internet community to maintain access to international services while complying with local and international laws.