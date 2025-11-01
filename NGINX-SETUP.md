# External Nginx Setup Guide

This guide explains how to set up nginx outside of Docker to work with the Docker Registry and Fail2ban container.

## Overview

The docker-compose setup now runs:
- **Docker Registry** (exposed on `127.0.0.1:5000`)
- **Redis** (for caching)
- **Fail2ban** (in host network mode to monitor external nginx logs)

Nginx runs **outside Docker** on the host system to provide SSL termination and reverse proxy.

## Prerequisites

1. Nginx installed on your host system
2. SSL certificates (Let's Encrypt recommended)
3. Docker and docker-compose installed

## Setup Instructions

### 1. Install Nginx (if not already installed)

### 2. Configure Nginx

#### Copy the configuration files:

sudo cp config/registry.conf /etc/nginx/conf.d/registry.conf

#### Edit the registry configuration:

```bash
sudo nano /etc/nginx/conf.d/registry.conf
```

**Update these values:**
- Replace `your-registry-domain.com` with your actual domain
- Update SSL certificate paths to match your setup

### 3. Configure Logging for Fail2ban

**IMPORTANT:** Fail2ban container monitors nginx logs at `/var/log/nginx/`. Ensure your nginx logs are written there:

#### Check nginx.conf logging configuration:
```nginx
access_log /var/log/nginx/access.log registry_log;
error_log /var/log/nginx/error.log warn;
```

#### Ensure the logs directory exists and is accessible:
```bash
sudo mkdir -p /var/log/nginx
sudo chown -R nginx:nginx /var/log/nginx  # or www-data:www-data on Debian/Ubuntu
```

### 4. Test and Reload Nginx

```bash
# Test nginx configuration
sudo nginx -t

# If test passes, reload nginx
sudo systemctl reload nginx

# Enable nginx to start on boot
sudo systemctl enable nginx
```

### 5. Start Docker Services

```bash
# Start the registry and fail2ban
docker-compose up -d
```

### 6. Verify the Setup

#### Check if registry is accessible locally:
```bash
curl http://127.0.0.1:5000/v2/
```

#### Check if nginx is proxying correctly:
```bash
curl -k https://your-registry-domain.com/v2/
```

#### Check fail2ban status:
```bash
docker-compose logs fail2ban
```

## Fail2ban Integration

### Active Jails

The following jails are enabled (see `config/fail2ban/jail.d/nginx-registry.conf`):

1. **nginx-http-auth** - Failed HTTP authentication attempts
2. **nginx-noscript** - Script kiddies attempting to exploit scripts
3. **nginx-badbots** - Known bad bots and scanners
4. **nginx-noproxy** - Attempts to use nginx as open proxy
5. **nginx-limit-req** - Rate limit violations
6. **docker-registry-auth** - Docker registry authentication failures

### Viewing Banned IPs

```bash
# View fail2ban status
docker exec registry-fail2ban fail2ban-client status

# View specific jail status
docker exec registry-fail2ban fail2ban-client status nginx-http-auth

# Unban an IP manually
docker exec registry-fail2ban fail2ban-client set nginx-http-auth unbanip 192.168.1.100
```

### Adjusting Ban Settings

Edit `config/fail2ban/jail.d/nginx-registry.conf` to adjust:
- `bantime` - How long to ban (default: 3600 seconds = 1 hour)
- `findtime` - Time window to count failures (default: 600 seconds)
- `maxretry` - Number of failures before ban (varies by jail)

After changes:
```bash
docker-compose restart fail2ban
```

### Permission Issues with Logs

```bash
# Ensure nginx can write to logs
sudo chown -R nginx:nginx /var/log/nginx

# Ensure fail2ban can read logs
sudo chmod 755 /var/log/nginx
sudo chmod 644 /var/log/nginx/*.log
```

## Security Recommendations

1. **Firewall Configuration:**
   ```bash
   # Allow only HTTP and HTTPS
   sudo ufw allow 80/tcp
   sudo ufw allow 443/tcp
   sudo ufw enable
   ```

2. **Keep SSL certificates updated** - Certbot handles this automatically

3. **Monitor fail2ban bans regularly:**
   ```bash
   docker exec registry-fail2ban fail2ban-client status
   ```

4. **Review nginx logs periodically:**
   ```bash
   sudo tail -f /var/log/nginx/access.log
   ```

5. **Update nginx regularly:**
   ```bash
   sudo apt update && sudo apt upgrade nginx
   ```
