#!/bin/bash

# Docker Registry Advanced User Management Script
# Supports role-based access control and repository-level permissions

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[1;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

HTPASSWD_FILE="auth/htpasswd"
ACL_FILE="auth/acl.yml"

# Function to print colored message and reset color
print_msg() {
    local color="$1"
    local message="$2"
    printf "${color}%s${NC}\n" "$message"
    tput sgr0 2>/dev/null || true
}

# Function to print without newline
print_msg_n() {
    local color="$1"
    local message="$2"
    printf "${color}%s${NC}" "$message"
    tput sgr0 2>/dev/null || true
}

# Function to reset terminal colors
reset_colors() {
    printf "${NC}"
    tput sgr0 2>/dev/null || true
}

# Trap to ensure colors are reset on exit
trap reset_colors EXIT INT TERM

# Check if htpasswd file exists, create if not
check_htpasswd() {
    if [ ! -f "$HTPASSWD_FILE" ]; then
        print_msg "$YELLOW" "Warning: $HTPASSWD_FILE not found!"
        echo "Creating auth directory..."
        mkdir -p auth
        touch "$HTPASSWD_FILE"
        print_msg "$GREEN" "✓ Created empty htpasswd file"
    fi
}

check_htpasswd

# Initialize ACL file if it doesn't exist
init_acl_file() {
    if [ ! -f "$ACL_FILE" ]; then
        cat > "$ACL_FILE" <<EOF
# Docker Registry ACL Configuration
# Define user permissions per repository
#
# Format:
#   users:
#     username:
#       role: admin|developer|reader
#       repositories:
#         - name: "repository-name"
#           actions: [pull, push, delete]
#
# Available actions:
#   - pull: Can pull images
#   - push: Can push images (implies pull)
#   - delete: Can delete images (requires push)
#
# Available roles:
#   - admin: Full access to all repositories
#   - developer: Can push/pull to assigned repositories
#   - reader: Can only pull from assigned repositories

users: {}
EOF
        print_msg "$GREEN" "✓ ACL file created"
    fi
}

# Function to parse ACL file and get user info
get_user_acl() {
    local username="$1"
    if [ -f "$ACL_FILE" ]; then
        grep -A 10 "^  $username:" "$ACL_FILE" 2>/dev/null || echo ""
    fi
}

# Function to check if user has ACL entry
has_acl_entry() {
    local username="$1"
    [ -f "$ACL_FILE" ] && grep -q "^  $username:" "$ACL_FILE" 2>/dev/null
    return $?
}

# Function to list users with their roles and permissions
list_users() {
    echo ""
    print_msg "$BLUE" "=========================================="
    print_msg "$BLUE" "Registry Users and Permissions"
    print_msg "$BLUE" "=========================================="
    echo ""
    
    if [ -s "$HTPASSWD_FILE" ]; then
        local count=1
        while IFS=: read -r username _; do
            # Skip empty lines
            [ -z "$username" ] && continue
            
            print_msg "$CYAN" "$count) $username"
            
            if has_acl_entry "$username"; then
                local role=$(grep -A 1 "^  $username:" "$ACL_FILE" 2>/dev/null | grep "role:" | sed 's/.*role: //' | tr -d ' ')
                print_msg "$YELLOW" "   Role: $role"
                
                echo "   Repositories:"
                local in_repos=0
                while IFS= read -r line; do
                    if [[ "$line" =~ -[[:space:]]name:[[:space:]]\"(.*)\" ]]; then
                        local repo="${BASH_REMATCH[1]}"
                        echo -n "     • $repo: "
                        in_repos=1
                    elif [[ "$line" =~ actions:[[:space:]](.*)$ ]] && [ $in_repos -eq 1 ]; then
                        local actions="${BASH_REMATCH[1]}"
                        print_msg "$GREEN" "$actions"
                        in_repos=0
                    fi
                done < <(grep -A 20 "^  $username:" "$ACL_FILE" 2>/dev/null || echo "")
            else
                print_msg "$YELLOW" "   No ACL permissions defined"
            fi
            echo ""
            count=$((count + 1))
        done < "$HTPASSWD_FILE"
    else
        echo "No users found."
    fi
}

# Function to add user
add_user() {
    echo ""
    print_msg "$BLUE" "=========================================="
    print_msg "$BLUE" "Add New User"
    print_msg "$BLUE" "=========================================="
    echo ""
    
    read -p "Enter username: " username
    
    # Check if user already exists
    if grep -q "^$username:" "$HTPASSWD_FILE" 2>/dev/null; then
        print_msg "$RED" "Error: User '$username' already exists!"
        return 1
    fi
    
    read -s -p "Enter password: " password
    echo ""
    read -s -p "Confirm password: " password_confirm
    echo ""
    
    if [ "$password" != "$password_confirm" ]; then
        print_msg "$RED" "Error: Passwords do not match!"
        return 1
    fi
    
    if [ -z "$password" ]; then
        print_msg "$RED" "Error: Password cannot be empty!"
        return 1
    fi
    
    # Add user using docker
    docker run --rm --entrypoint htpasswd httpd:2 -Bbn "$username" "$password" >> "$HTPASSWD_FILE" 2>/dev/null || {
        print_msg "$RED" "Error: Failed to add user. Make sure Docker is running."
        return 1
    }
    print_msg "$GREEN" "✓ User '$username' added to htpasswd"
    
    # Configure ACL
    echo ""
    echo "Configure access permissions for '$username':"
    echo "1) Admin (full access to all repositories)"
    echo "2) Developer (custom repository access)"
    echo "3) Reader (read-only access)"
    echo "4) Skip ACL configuration"
    echo ""
    read -p "Select role [1-4]: " role_choice
    
    case $role_choice in
        1)
            add_user_acl "$username" "admin" ""
            ;;
        2)
            add_user_acl "$username" "developer" "custom"
            ;;
        3)
            add_user_acl "$username" "reader" "custom"
            ;;
        4)
            echo "Skipping ACL configuration"
            ;;
        *)
            echo "Invalid choice, skipping ACL configuration"
            ;;
    esac
    
    print_msg "$GREEN" "✓ User '$username' added successfully"
    
    # Restart registry to apply changes
    read -p "Do you want to restart the registry to apply changes? (y/N): " restart
    if [ "$restart" = "y" ] || [ "$restart" = "Y" ]; then
        docker compose restart registry
        print_msg "$GREEN" "✓ Registry restarted"
    fi
}

# Function to add ACL entry for user
add_user_acl() {
    local username="$1"
    local role="$2"
    local config_type="$3"
    
    init_acl_file
    
    # Check if user already has ACL entry
    if has_acl_entry "$username"; then
        print_msg "$YELLOW" "User '$username' already has ACL entry. Use 'Edit permissions' to modify."
        return 0
    fi
    
    # Backup ACL file
    cp "$ACL_FILE" "${ACL_FILE}.bak"
    
    if [ "$role" = "admin" ]; then
        # Admin role - full access
        cat >> "$ACL_FILE" <<EOF
  $username:
    role: admin
    repositories:
      - name: "*"
        actions: [pull, push, delete]
EOF
        print_msg "$GREEN" "✓ Admin role assigned to '$username'"
        
    elif [ "$config_type" = "custom" ]; then
        # Custom repository access
        cat >> "$ACL_FILE" <<EOF
  $username:
    role: $role
    repositories: []
EOF
        print_msg "$GREEN" "✓ $role role assigned to '$username'"
        echo ""
        read -p "Do you want to add repository permissions now? (y/N): " add_perms
        if [ "$add_perms" = "y" ] || [ "$add_perms" = "Y" ]; then
            add_repository_permission "$username"
        fi
    fi
}

# Function to add repository permission to user
add_repository_permission() {
    local username="$1"
    
    if [ -z "$username" ]; then
        echo ""
        list_users
        read -p "Enter username: " username
    fi
    
    if ! has_acl_entry "$username"; then
        print_msg "$RED" "Error: User '$username' has no ACL entry. Add user first."
        return 1
    fi
    
    echo ""
    echo "Add repository permission for '$username':"
    read -p "Repository name (or * for all): " repo_name
    
    if [ -z "$repo_name" ]; then
        print_msg "$RED" "Error: Repository name cannot be empty!"
        return 1
    fi
    
    echo ""
    echo "Select permissions:"
    echo "1) Pull only (read-only)"
    echo "2) Pull & Push (read-write)"
    echo "3) Pull, Push & Delete (full access)"
    echo ""
    read -p "Select [1-3]: " perm_choice
    
    local actions=""
    case $perm_choice in
        1)
            actions="[pull]"
            ;;
        2)
            actions="[pull, push]"
            ;;
        3)
            actions="[pull, push, delete]"
            ;;
        *)
            print_msg "$RED" "Invalid choice"
            return 1
            ;;
    esac
    
    # Backup ACL file
    cp "$ACL_FILE" "${ACL_FILE}.bak"
    
    # Add repository permission
    local temp_file="${ACL_FILE}.tmp"
    local in_user=0
    local added=0
    
    while IFS= read -r line; do
        echo "$line" >> "$temp_file"
        
        if [[ "$line" =~ ^[[:space:]]*$username: ]]; then
            in_user=1
        elif [ $in_user -eq 1 ] && [[ "$line" =~ ^[[:space:]]*repositories:[[:space:]]*\[\]?$ ]]; then
            echo "      - name: \"$repo_name\"" >> "$temp_file"
            echo "        actions: $actions" >> "$temp_file"
            added=1
            in_user=0
        elif [ $in_user -eq 1 ] && [[ "$line" =~ ^[[:space:]]*-[[:space:]]name: ]]; then
            in_user=0
        fi
    done < "$ACL_FILE"
    
    if [ $added -eq 0 ]; then
        local line_num=$(grep -n "^  $username:" "$ACL_FILE" | cut -d: -f1)
        local repo_line=$(tail -n +$line_num "$ACL_FILE" | grep -n "repositories:" | head -1 | cut -d: -f1)
        
        if [ -n "$repo_line" ]; then
            awk -v user="$username" -v repo="$repo_name" -v acts="$actions" '
                BEGIN { in_user=0; last_repo_line=0 }
                /^  [a-z]/ { if (in_user && last_repo_line > 0) { 
                    print "      - name: \"" repo "\"";
                    print "        actions: " acts;
                    last_repo_line=0;
                    in_user=0;
                }}
                { print }
                $0 ~ "^  " user ":" { in_user=1 }
                in_user && /^      - name:/ { last_repo_line=NR }
                END { if (in_user && last_repo_line > 0) {
                    print "      - name: \"" repo "\"";
                    print "        actions: " acts;
                }}
            ' "$ACL_FILE" > "$temp_file"
        fi
    fi
    
    mv "$temp_file" "$ACL_FILE"
    
    print_msg "$GREEN" "✓ Repository permission added"
    echo "   Repository: $repo_name"
    echo "   Actions: $actions"
}

# Function to remove user
remove_user() {
    echo ""
    print_msg "$BLUE" "=========================================="
    print_msg "$BLUE" "Remove User"
    print_msg "$BLUE" "=========================================="
    echo ""
    
    list_users
    
    read -p "Enter username to remove: " username
    
    if ! grep -q "^$username:" "$HTPASSWD_FILE" 2>/dev/null; then
        print_msg "$RED" "Error: User '$username' not found!"
        return 1
    fi
    
    read -p "Are you sure you want to remove user '$username'? (y/N): " confirm
    if [ "$confirm" != "y" ] && [ "$confirm" != "Y" ]; then
        echo "Operation cancelled."
        return 0
    fi
    
    # Create backups
    cp "$HTPASSWD_FILE" "${HTPASSWD_FILE}.bak"
    if [ -f "$ACL_FILE" ]; then
        cp "$ACL_FILE" "${ACL_FILE}.bak"
    fi
    
    # Remove from htpasswd
    grep -v "^$username:" "$HTPASSWD_FILE" > "${HTPASSWD_FILE}.tmp" && mv "${HTPASSWD_FILE}.tmp" "$HTPASSWD_FILE"
    
    # Remove from ACL
    if [ -f "$ACL_FILE" ] && has_acl_entry "$username"; then
        awk -v user="$username" '
            BEGIN { skip=0 }
            /^  [a-z]/ { skip=0 }
            $0 ~ "^  " user ":" { skip=1; next }
            skip == 0 { print }
        ' "$ACL_FILE" > "${ACL_FILE}.tmp" && mv "${ACL_FILE}.tmp" "$ACL_FILE"
    fi
    
    print_msg "$GREEN" "✓ User '$username' removed successfully"
    print_msg "$YELLOW" "Backups saved"
    
    # Restart registry to apply changes
    read -p "Do you want to restart the registry to apply changes? (y/N): " restart
    if [ "$restart" = "y" ] || [ "$restart" = "Y" ]; then
        docker compose restart registry
        print_msg "$GREEN" "✓ Registry restarted"
    fi
}

# Function to change user password
change_password() {
    echo ""
    print_msg "$BLUE" "=========================================="
    print_msg "$BLUE" "Change User Password"
    print_msg "$BLUE" "=========================================="
    echo ""
    
    list_users
    
    read -p "Enter username: " username
    
    if ! grep -q "^$username:" "$HTPASSWD_FILE" 2>/dev/null; then
        print_msg "$RED" "Error: User '$username' not found!"
        return 1
    fi
    
    read -s -p "Enter new password: " password
    echo ""
    read -s -p "Confirm new password: " password_confirm
    echo ""
    
    if [ "$password" != "$password_confirm" ]; then
        print_msg "$RED" "Error: Passwords do not match!"
        return 1
    fi
    
    if [ -z "$password" ]; then
        print_msg "$RED" "Error: Password cannot be empty!"
        return 1
    fi
    
    # Create backup
    cp "$HTPASSWD_FILE" "${HTPASSWD_FILE}.bak"
    
    # Remove old entry and add new one
    grep -v "^$username:" "$HTPASSWD_FILE" > "${HTPASSWD_FILE}.tmp"
    docker run --rm --entrypoint htpasswd httpd:2 -Bbn "$username" "$password" >> "${HTPASSWD_FILE}.tmp" 2>/dev/null || {
        print_msg "$RED" "Error: Failed to change password. Make sure Docker is running."
        rm -f "${HTPASSWD_FILE}.tmp"
        return 1
    }
    mv "${HTPASSWD_FILE}.tmp" "$HTPASSWD_FILE"
    
    print_msg "$GREEN" "✓ Password changed successfully"
    
    # Restart registry to apply changes
    read -p "Do you want to restart the registry to apply changes? (y/N): " restart
    if [ "$restart" = "y" ] || [ "$restart" = "Y" ]; then
        docker compose restart registry
        print_msg "$GREEN" "✓ Registry restarted"
    fi
}

# Function to edit user permissions
edit_permissions() {
    echo ""
    print_msg "$BLUE" "=========================================="
    print_msg "$BLUE" "Edit User Permissions"
    print_msg "$BLUE" "=========================================="
    echo ""
    
    list_users
    
    read -p "Enter username: " username
    
    if ! grep -q "^$username:" "$HTPASSWD_FILE" 2>/dev/null; then
        print_msg "$RED" "Error: User '$username' not found!"
        return 1
    fi
    
    if ! has_acl_entry "$username"; then
        print_msg "$YELLOW" "User has no ACL configuration"
        read -p "Do you want to create ACL entry? (y/N): " create
        if [ "$create" = "y" ] || [ "$create" = "Y" ]; then
            echo ""
            echo "Select role:"
            echo "1) Admin"
            echo "2) Developer"
            echo "3) Reader"
            read -p "Select [1-3]: " role_choice
            
            case $role_choice in
                1) add_user_acl "$username" "admin" "" ;;
                2) add_user_acl "$username" "developer" "custom" ;;
                3) add_user_acl "$username" "reader" "custom" ;;
                *) print_msg "$RED" "Invalid choice"; return 1 ;;
            esac
        fi
        return 0
    fi
    
    echo ""
    echo "Edit permissions for '$username':"
    echo "1) Change role"
    echo "2) Add repository permission"
    echo "3) Remove repository permission"
    echo "4) View current permissions"
    echo "5) Back"
    echo ""
    read -p "Select [1-5]: " edit_choice
    
    case $edit_choice in
        1)
            change_user_role "$username"
            ;;
        2)
            add_repository_permission "$username"
            ;;
        3)
            remove_repository_permission "$username"
            ;;
        4)
            show_user_info "$username"
            ;;
        5)
            return 0
            ;;
        *)
            print_msg "$RED" "Invalid choice"
            ;;
    esac
}

# Function to change user role
change_user_role() {
    local username="$1"
    
    echo ""
    echo "Select new role for '$username':"
    echo "1) Admin"
    echo "2) Developer"
    echo "3) Reader"
    read -p "Select [1-3]: " role_choice
    
    local new_role=""
    case $role_choice in
        1) new_role="admin" ;;
        2) new_role="developer" ;;
        3) new_role="reader" ;;
        *) print_msg "$RED" "Invalid choice"; return 1 ;;
    esac
    
    # Backup ACL file
    cp "$ACL_FILE" "${ACL_FILE}.bak"
    
    # Update role in ACL file
    sed -i.tmp "/^  $username:/,/^  [a-z]/ s/role: .*/role: $new_role/" "$ACL_FILE"
    rm -f "${ACL_FILE}.tmp"
    
    print_msg "$GREEN" "✓ Role changed to '$new_role'"
}

# Function to remove repository permission
remove_repository_permission() {
    local username="$1"
    
    echo ""
    echo "Current repositories for '$username':"
    local count=1
    local repos=()
    
    while IFS= read -r line; do
        if [[ "$line" =~ ^[[:space:]]*-[[:space:]]name:[[:space:]]\"(.*)\" ]]; then
            local repo="${BASH_REMATCH[1]}"
            repos+=("$repo")
            echo "$count) $repo"
            ((count++))
        fi
    done < <(grep -A 20 "^  $username:" "$ACL_FILE")
    
    if [ ${#repos[@]} -eq 0 ]; then
        echo "No repository permissions found"
        return 0
    fi
    
    echo ""
    read -p "Select repository to remove [1-${#repos[@]}]: " repo_choice
    
    if [ "$repo_choice" -lt 1 ] || [ "$repo_choice" -gt ${#repos[@]} ]; then
        print_msg "$RED" "Invalid choice"
        return 1
    fi
    
    local repo_to_remove="${repos[$((repo_choice-1))]}"
    
    # Backup ACL file
    cp "$ACL_FILE" "${ACL_FILE}.bak"
    
    # Remove repository entry
    local temp_file="${ACL_FILE}.tmp"
    local skip_lines=0
    
    while IFS= read -r line; do
        if [ $skip_lines -gt 0 ]; then
            ((skip_lines--))
            continue
        fi
        
        if [[ "$line" =~ ^[[:space:]]*-[[:space:]]name:[[:space:]]\"$repo_to_remove\" ]]; then
            skip_lines=1
            continue
        fi
        
        echo "$line" >> "$temp_file"
    done < "$ACL_FILE"
    
    mv "$temp_file" "$ACL_FILE"
    
    print_msg "$GREEN" "✓ Repository permission removed"
}

# Function to show user info
show_user_info() {
    local username="$1"
    
    if [ -z "$username" ]; then
        echo ""
        print_msg "$BLUE" "=========================================="
        print_msg "$BLUE" "User Information"
        print_msg "$BLUE" "=========================================="
        echo ""
        read -p "Enter username: " username
    fi
    
    if ! grep -q "^$username:" "$HTPASSWD_FILE" 2>/dev/null; then
        print_msg "$RED" "Error: User '$username' not found!"
        return 1
    fi
    
    echo ""
    print_msg "$CYAN" "Username: $username"
    print_msg "$GREEN" "Status: Active"
    
    if has_acl_entry "$username"; then
        local role=$(grep -A 1 "^  $username:" "$ACL_FILE" | grep "role:" | sed 's/.*role: //' | tr -d ' ')
        print_msg "$YELLOW" "Role: $role"
        
        echo ""
        echo "Repository Permissions:"
        local in_repos=0
        while IFS= read -r line; do
            if [[ "$line" =~ -[[:space:]]name:[[:space:]]\"(.*)\" ]]; then
                local repo="${BASH_REMATCH[1]}"
                echo -n "  • $repo: "
                in_repos=1
            elif [[ "$line" =~ actions:[[:space:]](.*)$ ]] && [ $in_repos -eq 1 ]; then
                local actions="${BASH_REMATCH[1]}"
                print_msg "$GREEN" "$actions"
                in_repos=0
            fi
        done < <(grep -A 20 "^  $username:" "$ACL_FILE" 2>/dev/null || echo "")
    else
        print_msg "$YELLOW" "No ACL permissions defined"
    fi
    echo ""
}

# Function to export ACL to readable format
export_acl() {
    echo ""
    print_msg "$BLUE" "=========================================="
    print_msg "$BLUE" "Export ACL Configuration"
    print_msg "$BLUE" "=========================================="
    echo ""
    
    if [ ! -f "$ACL_FILE" ]; then
        echo "No ACL file found"
        return 0
    fi
    
    local export_file="acl-export-$(date +%Y%m%d-%H%M%S).txt"
    
    echo "Docker Registry Access Control List" > "$export_file"
    echo "Generated: $(date)" >> "$export_file"
    echo "========================================" >> "$export_file"
    echo "" >> "$export_file"
    
    while IFS=: read -r username _; do
        # Skip empty lines
        [ -z "$username" ] && continue
        
        if has_acl_entry "$username"; then
            echo "User: $username" >> "$export_file"
            local role=$(grep -A 1 "^  $username:" "$ACL_FILE" | grep "role:" | sed 's/.*role: //' | tr -d ' ')
            echo "Role: $role" >> "$export_file"
            echo "Repositories:" >> "$export_file"
            
            local in_repos=0
            while IFS= read -r line; do
                if [[ "$line" =~ -[[:space:]]name:[[:space:]]\"(.*)\" ]]; then
                    local repo="${BASH_REMATCH[1]}"
                    echo -n "  - $repo: " >> "$export_file"
                    in_repos=1
                elif [[ "$line" =~ actions:[[:space:]](.*)$ ]] && [ $in_repos -eq 1 ]; then
                    local actions="${BASH_REMATCH[1]}"
                    echo "$actions" >> "$export_file"
                    in_repos=0
                fi
            done < <(grep -A 20 "^  $username:" "$ACL_FILE" 2>/dev/null || echo "")
            
            echo "" >> "$export_file"
        fi
    done < "$HTPASSWD_FILE"
    
    print_msg "$GREEN" "✓ ACL exported to $export_file"
}

# Main menu
show_menu() {
    echo ""
    print_msg "$BLUE" "=========================================="
    print_msg "$BLUE" "Docker Registry User Management"
    print_msg "$BLUE" "Role-Based Access Control (RBAC)"
    print_msg "$BLUE" "=========================================="
    echo ""
    echo "User Management:"
    echo "  1) List all users"
    echo "  2) Add new user"
    echo "  3) Remove user"
    echo "  4) Change user password"
    echo "  5) Show user info"
    echo ""
    echo "Permission Management:"
    echo "  6) Edit user permissions"
    echo "  7) Add repository permission"
    echo "  8) Export ACL configuration"
    echo ""
    echo "  9) Exit"
    echo ""
}

# Initialize ACL file if needed
init_acl_file

# Main loop
while true; do
    show_menu
    read -p "Enter choice [1-9]: " choice
    
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
            show_user_info ""
            ;;
        6)
            edit_permissions
            ;;
        7)
            add_repository_permission ""
            ;;
        8)
            export_acl
            ;;
        9)
            reset_colors
            echo ""
            echo "Exiting..."
            exit 0
            ;;
        *)
            print_msg "$RED" "Invalid choice. Please try again."
            ;;
    esac
    
    read -p "Press Enter to continue..."
done
