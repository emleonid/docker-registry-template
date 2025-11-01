# Quick Start Guide - Secure Docker Registry

📘 **For detailed nginx setup instructions, see [NGINX-SETUP.md](NGINX-SETUP.md)**

### Architecture

```
Internet → [Host Nginx :80/:443] ← [Fail2ban Container monitors logs]
              ↓
          [Docker Registry :5000]
              ↓
          [Redis Cache]
              ↓
          [Cloudflare R2 Storage]
```

### Run Setup

```bash
# Make scripts executable
chmod +x setup.sh manage-users.sh

# Run setup (choose option 1 for self-signed cert if testing)
./setup.sh
```

### Start Services

```bash
docker compose up -d
```

## Usage Examples

### Login
```bash
docker login registry.yourdomain.com:443
# Enter username and password when prompted
```

### Push an Image
```bash
# Tag your image
docker tag myapp:latest registry.yourdomain.com:443/myapp:latest

# Push
docker push registry.yourdomain.com:443/myapp:latest
```

### Pull an Image
```bash
docker pull registry.yourdomain.com:443/myapp:latest
```

### List All Images
```bash
curl -u username:password https://registry.yourdomain.com/v2/_catalog
```

## User Management

```bash
# Run user management script
./manage-users.sh

# Options:
# 1 - List users
# 2 - Add user
# 3 - Remove user
# 4 - Change password
```

## Common Commands

```bash
# View logs
docker compose logs -f

# Stop services
docker compose down

# Restart services
docker compose restart

# Update and restart
docker compose pull && docker compose up -d
```
