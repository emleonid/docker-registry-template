#!/bin/bash

# Docker Registry User Management Script
# This script manages users for the Docker Registry

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

HTPASSWD_FILE="auth/htpasswd"

# Check if htpasswd file exists
if [ ! -f "$HTPASSWD_FILE" ]; then
    echo -e "${RED}Error: $HTPASSWD_FILE not found!${NC}"
    echo "Please run ./setup.sh first to initialize the registry."
    exit 1
fi

# Function to list users
list_users() {
    echo ""
    echo -e "${BLUE}==========================================
Current Registry Users
==========================================${NC}"
    echo ""
    
    if [ -s "$HTPASSWD_FILE" ]; then
        cat "$HTPASSWD_FILE" | cut -d: -f1 | nl
    else
        echo "No users found."
    fi
    echo ""
}

# Function to add user
add_user() {
    echo ""
    echo -e "${BLUE}==========================================
Add New User
==========================================${NC}"
    echo ""
    
    read -p "Enter username: " username
    
    # Check if user already exists
    if grep -q "^$username:" "$HTPASSWD_FILE" 2>/dev/null; then
        echo -e "${RED}Error: User '$username' already exists!${NC}"
        return 1
    fi
    
    read -s -p "Enter password: " password
    echo ""
    read -s -p "Confirm password: " password_confirm
    echo ""
    
    if [ "$password" != "$password_confirm" ]; then
        echo -e "${RED}Error: Passwords do not match!${NC}"
        return 1
    fi
    
    if [ -z "$password" ]; then
        echo -e "${RED}Error: Password cannot be empty!${NC}"
        return 1
    fi
    
    # Add user using docker
    docker run --rm --entrypoint htpasswd httpd:2 -Bbn "$username" "$password" >> "$HTPASSWD_FILE"
    
    echo -e "${GREEN}✓ User '$username' added successfully${NC}"
    
    # Restart registry to apply changes
    read -p "Do you want to restart the registry to apply changes? (y/N): " restart
    if [ "$restart" = "y" ] || [ "$restart" = "Y" ]; then
        docker compose restart registry
        echo -e "${GREEN}✓ Registry restarted${NC}"
    fi
}

# Function to remove user
remove_user() {
    echo ""
    echo -e "${BLUE}==========================================
Remove User
==========================================${NC}"
    echo ""
    
    list_users
    
    read -p "Enter username to remove: " username
    
    if ! grep -q "^$username:" "$HTPASSWD_FILE" 2>/dev/null; then
        echo -e "${RED}Error: User '$username' not found!${NC}"
        return 1
    fi
    
    read -p "Are you sure you want to remove user '$username'? (y/N): " confirm
    if [ "$confirm" != "y" ] && [ "$confirm" != "Y" ]; then
        echo "Operation cancelled."
        return 0
    fi
    
    # Create backup
    cp "$HTPASSWD_FILE" "${HTPASSWD_FILE}.bak"
    
    # Remove user
    grep -v "^$username:" "$HTPASSWD_FILE" > "${HTPASSWD_FILE}.tmp" && mv "${HTPASSWD_FILE}.tmp" "$HTPASSWD_FILE"
    
    echo -e "${GREEN}✓ User '$username' removed successfully${NC}"
    echo -e "${YELLOW}Backup saved to ${HTPASSWD_FILE}.bak${NC}"
    
    # Restart registry to apply changes
    read -p "Do you want to restart the registry to apply changes? (y/N): " restart
    if [ "$restart" = "y" ] || [ "$restart" = "Y" ]; then
        docker compose restart registry
        echo -e "${GREEN}✓ Registry restarted${NC}"
    fi
}

# Function to change user password
change_password() {
    echo ""
    echo -e "${BLUE}==========================================
Change User Password
==========================================${NC}"
    echo ""
    
    list_users
    
    read -p "Enter username: " username
    
    if ! grep -q "^$username:" "$HTPASSWD_FILE" 2>/dev/null; then
        echo -e "${RED}Error: User '$username' not found!${NC}"
        return 1
    fi
    
    read -s -p "Enter new password: " password
    echo ""
    read -s -p "Confirm new password: " password_confirm
    echo ""
    
    if [ "$password" != "$password_confirm" ]; then
        echo -e "${RED}Error: Passwords do not match!${NC}"
        return 1
    fi
    
    if [ -z "$password" ]; then
        echo -e "${RED}Error: Password cannot be empty!${NC}"
        return 1
    fi
    
    # Create backup
    cp "$HTPASSWD_FILE" "${HTPASSWD_FILE}.bak"
    
    # Remove old entry and add new one
    grep -v "^$username:" "$HTPASSWD_FILE" > "${HTPASSWD_FILE}.tmp"
    docker run --rm --entrypoint htpasswd httpd:2 -Bbn "$username" "$password" >> "${HTPASSWD_FILE}.tmp"
    mv "${HTPASSWD_FILE}.tmp" "$HTPASSWD_FILE"
    
    echo -e "${GREEN}✓ Password for user '$username' changed successfully${NC}"
    echo -e "${YELLOW}Backup saved to ${HTPASSWD_FILE}.bak${NC}"
    
    # Restart registry to apply changes
    read -p "Do you want to restart the registry to apply changes? (y/N): " restart
    if [ "$restart" = "y" ] || [ "$restart" = "Y" ]; then
        docker compose restart registry
        echo -e "${GREEN}✓ Registry restarted${NC}"
    fi
}

# Function to show user info
show_user_info() {
    echo ""
    echo -e "${BLUE}==========================================
User Information
==========================================${NC}"
    echo ""
    
    read -p "Enter username: " username
    
    if grep -q "^$username:" "$HTPASSWD_FILE" 2>/dev/null; then
        echo ""
        echo "Username: $username"
        echo "Status: Active"
        echo -e "${GREEN}✓ User exists in registry${NC}"
    else
        echo -e "${RED}Error: User '$username' not found!${NC}"
    fi
    echo ""
}

# Main menu
show_menu() {
    echo ""
    echo -e "${BLUE}==========================================
Docker Registry User Management
==========================================${NC}"
    echo ""
    echo "1) List all users"
    echo "2) Add new user"
    echo "3) Remove user"
    echo "4) Change user password"
    echo "5) Show user info"
    echo "6) Exit"
    echo ""
}

# Main loop
while true; do
    show_menu
    read -p "Enter choice [1-6]: " choice
    
    case $choice in
        1)
            list_users
            ;;
        2)
            add_user
            ;;
        3)
            remove_user
            ;;
        4)
            change_password
            ;;
        5)
            show_user_info
            ;;
        6)
            echo ""
            echo "Exiting..."
            exit 0
            ;;
        *)
            echo -e "${RED}Invalid choice. Please try again.${NC}"
            ;;
    esac
    
    read -p "Press Enter to continue..."
done
