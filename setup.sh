#!/bin/bash

# Docker Registry Setup Script
# This script sets up the Docker Registry with authentication and SSL

set -e

echo "=========================================="
echo "Docker Registry Setup"
echo "=========================================="
echo ""

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Load environment variables
if [ -f .env ]; then
    export $(cat .env | grep -v '^#' | xargs)
else
    echo -e "${RED}Error: .env file not found!${NC}"
    exit 1
fi

# Function to check if command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Check required commands
echo "Checking required tools..."
REQUIRED_COMMANDS="docker openssl"
for cmd in $REQUIRED_COMMANDS; do
    if ! command_exists $cmd; then
        echo -e "${RED}Error: $cmd is not installed. Please install it first.${NC}"
        exit 1
    fi
done
echo -e "${GREEN}✓ All required tools are installed${NC}"
echo ""

# Create necessary directories
echo "Creating directory structure..."
mkdir -p auth storage config/fail2ban/jail.d config/fail2ban/filter.d
echo -e "${GREEN}✓ Directories created${NC}"
echo ""

# Cloudflare R2 Configuration Check
echo "=========================================="
echo "Cloudflare R2 Storage Configuration"
echo "=========================================="
echo ""
echo "This registry uses Cloudflare R2 for storage."
echo "You need to configure R2 credentials in the .env file."
echo ""

if [ "$R2_ACCESS_KEY_ID" = "YOUR_R2_ACCESS_KEY_ID" ] || [ "$R2_SECRET_ACCESS_KEY" = "YOUR_R2_SECRET_ACCESS_KEY" ]; then
    echo -e "${YELLOW}WARNING: R2 credentials not configured!${NC}"
    echo ""
    echo "Please update the following in your .env file:"
    echo "  - R2_ACCESS_KEY_ID"
    echo "  - R2_SECRET_ACCESS_KEY"
    echo "  - R2_BUCKET"
    echo "  - R2_ACCOUNT_ID"
    echo ""
    echo "Get these from: https://dash.cloudflare.com/ > R2 > Manage R2 API Tokens"
    echo ""
    read -p "Have you configured R2 credentials in .env? (y/N): " r2_configured
    
    if [ "$r2_configured" != "y" ] && [ "$r2_configured" != "Y" ]; then
        echo -e "${RED}Please configure R2 credentials before proceeding.${NC}"
        echo "Exiting setup..."
        exit 1
    fi
fi

echo -e "${GREEN}✓ R2 configuration verified${NC}"
echo ""

# Generate Registry HTTP Secret if not set
if [ "$REGISTRY_HTTP_SECRET" = "CHANGE_THIS_TO_RANDOM_SECRET_STRING" ]; then
    echo "Generating random registry secret..."
    NEW_SECRET=$(openssl rand -hex 32)
    sed -i.bak "s/REGISTRY_HTTP_SECRET=.*/REGISTRY_HTTP_SECRET=$NEW_SECRET/" .env
    echo -e "${GREEN}✓ Registry secret generated and saved to .env${NC}"
    echo ""
fi

# Setup authentication
echo "=========================================="
echo "User Authentication Setup"
echo "=========================================="
echo ""

# Check if htpasswd file already exists
if [ -f "auth/htpasswd" ]; then
    echo -e "${YELLOW}Warning: auth/htpasswd file already exists${NC}"
    read -p "Do you want to recreate it? (y/N): " recreate
    if [ "$recreate" != "y" ] && [ "$recreate" != "Y" ]; then
        echo "Keeping existing auth/htpasswd file"
    else
        rm -f auth/htpasswd
        echo "Removed existing auth/htpasswd file"
    fi
fi

if [ ! -f "auth/htpasswd" ]; then
    echo "Creating authentication file..."
    echo ""
    
    # Get admin credentials from .env
    ADMIN_USER=${REGISTRY_ADMIN_USER:-admin}
    ADMIN_PASS=${REGISTRY_ADMIN_PASSWORD}
    
    if [ "$ADMIN_PASS" = "CHANGE_THIS_STRONG_PASSWORD" ]; then
        echo -e "${YELLOW}Please set a strong admin password:${NC}"
        read -s -p "Enter password for user '$ADMIN_USER': " ADMIN_PASS
        echo ""
        read -s -p "Confirm password: " ADMIN_PASS_CONFIRM
        echo ""
        
        if [ "$ADMIN_PASS" != "$ADMIN_PASS_CONFIRM" ]; then
            echo -e "${RED}Error: Passwords do not match!${NC}"
            exit 1
        fi
    fi
    
    # Create htpasswd file using docker
    docker run --rm --entrypoint htpasswd httpd:2 -Bbn "$ADMIN_USER" "$ADMIN_PASS" > auth/htpasswd
    
    echo -e "${GREEN}✓ Admin user '$ADMIN_USER' created${NC}"
    echo ""
fi

# Function to add more users
add_more_users() {
    while true; do
        read -p "Do you want to add another user? (y/N): " add_user
        if [ "$add_user" != "y" ] && [ "$add_user" != "Y" ]; then
            break
        fi
        
        echo ""
        read -p "Enter username: " username
        read -s -p "Enter password: " password
        echo ""
        read -s -p "Confirm password: " password_confirm
        echo ""
        
        if [ "$password" != "$password_confirm" ]; then
            echo -e "${RED}Error: Passwords do not match!${NC}"
            continue
        fi
        
        docker run --rm --entrypoint htpasswd httpd:2 -Bbn "$username" "$password" >> auth/htpasswd
        echo -e "${GREEN}✓ User '$username' added${NC}"
        echo ""
    done
}

add_more_users

# Set proper permissions for auth file
chmod 644 auth/htpasswd

echo ""
echo "=========================================="
echo "Configuration Summary"
echo "=========================================="
echo ""
echo "Registry Domain: $REGISTRY_DOMAIN"
echo "Registry Port (HTTPS): $REGISTRY_PORT"
echo "Registry Port (HTTP): $REGISTRY_HTTP_PORT"
echo "Data Directory: $(pwd)/data"
echo "Auth File: $(pwd)/auth/htpasswd"
echo ""

echo "=========================================="
echo "Security Features Enabled"
echo "=========================================="
echo ""
echo "✓ HTTPS/TLS encryption (TLS 1.2+)"
echo "✓ HTTP Basic Authentication (htpasswd)"
echo "✓ Rate limiting (connection and request limits)"
echo "✓ DDoS protection (multiple layers)"
echo "✓ Fail2ban integration"
echo "✓ Security headers (HSTS, X-Frame-Options, etc.)"
echo "✓ Bad bot blocking"
echo "✓ Request size limits"
echo ""

echo "=========================================="
echo "Next Steps"
echo "=========================================="
echo ""
echo "1. Review and update .env file with your domain AND GENERATE SSL Certificates"
echo "2. Start the registry:"
echo "   docker compose up -d"
echo ""
echo "3. Check logs:"
echo "   docker compose logs -f"
echo ""
echo "4. Test the registry:"
echo "   docker login $REGISTRY_DOMAIN:$REGISTRY_PORT"
echo ""
echo "5. Push an image:"
echo "   docker tag myimage $REGISTRY_DOMAIN:$REGISTRY_PORT/myimage"
echo "   docker push $REGISTRY_DOMAIN:$REGISTRY_PORT/myimage"
echo ""
echo "6. For production, consider:"
echo "   - Using Let's Encrypt for SSL certificates"
echo "   - Setting up proper DNS for your domain"
echo "   - Configuring firewall rules"
echo "   - Regular backups of ./data directory"
echo ""

echo -e "${GREEN}Setup completed successfully!${NC}"
