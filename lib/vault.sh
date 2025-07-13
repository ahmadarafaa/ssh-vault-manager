#!/bin/bash

# ============================================================================
# VAULT MANAGEMENT MODULE
# ============================================================================

# Use the version from config.sh (SVM_VERSION)

# Initialize vault management system
init_vault_system() {
    # Create base directories
    if ! secure_directory_operation "create" "$base_vault_dir"; then
        echo -e "${RED}Failed to create secure base directory.${NC}"
        return 1
    fi
    
    if ! secure_directory_operation "create" "$vaults_dir"; then
        echo -e "${RED}Failed to create secure vaults directory.${NC}"
        return 1
    fi
    
    # Create vault registry file
    local vault_registry="$base_vault_dir/.vault_registry"
    if [[ ! -f "$vault_registry" ]]; then
        touch "$vault_registry"
        chmod 600 "$vault_registry"
        
        # Verify file integrity
        if ! verify_file_ownership "$vault_registry" || ! verify_file_permissions "$vault_registry"; then
            echo -e "${RED}Failed to create secure vault registry.${NC}"
            return 1
        fi
    fi
    
    # Register any existing vaults that aren't in the registry
    register_existing_vaults
    
    log_security_event "VAULT_SYSTEM_INITIALIZED" "Vault management system initialized securely" "INFO"
}

# Load current vault from indicator file
load_current_vault() {
    local current_vault_file="$base_vault_dir/.current_vault"
    if [[ -f "$current_vault_file" ]]; then
        current_vault_name=$(cat "$current_vault_file")
        if [[ -n "$current_vault_name" && -d "$vaults_dir/$current_vault_name" ]]; then
            vault="$vaults_dir/$current_vault_name"
            init_file_paths
            return 0
        fi
    fi
    return 1
}

# Register existing vaults in registry
register_existing_vaults() {
    local vault_registry="$base_vault_dir/.vault_registry"
    
    # Check if vaults directory exists
    if [[ ! -d "$vaults_dir" ]]; then
        return 0
    fi
    
    # Get list of existing vaults
    local existing_vaults=()
    for vault_path in "$vaults_dir"/*; do
        if [[ -d "$vault_path" ]]; then
            local vault_name=$(basename "$vault_path")
            existing_vaults+=("$vault_name")
        fi
    done
    
    # Check which vaults are not in registry
    for vault_name in "${existing_vaults[@]}"; do
        if ! grep -q "^$vault_name|" "$vault_registry" 2>/dev/null; then
            # Register the vault
            echo "$vault_name|$(date '+%Y-%m-%d %H:%M:%S')|$(whoami)" >> "$vault_registry"
            log_event "VAULT_REGISTERED" "Existing vault registered: $vault_name"
        fi
    done
}

# Load configuration file
load_config() {
    if [[ -f "$config_file" ]]; then
        while IFS='=' read -r key value; do
            # Skip comments and empty lines
            [[ "$key" =~ ^[[:space:]]*# ]] && continue
            [[ -z "$key" ]] && continue
            
            # Remove quotes from value
            value=$(echo "$value" | sed 's/^["'\'']//' | sed 's/["'\'']$//')
            CONFIG["$key"]="$value"
        done < "$config_file"
        
        log_event "CONFIG_LOADED" "Configuration loaded from $config_file"
    fi
}

# Save default configuration
save_default_config() {
    if [[ ! -f "$config_file" ]]; then
        cat > "$config_file" << 'EOF'
# SVM Configuration File
PBKDF2_ITERATIONS=600000
CIPHER=aes-256-cbc
DIGEST=sha512
VAULT_VERSION=${SVM_VERSION%.*}
PASSPHRASE_TIMEOUT=300
MAX_LOGIN_ATTEMPTS=3
CONNECTION_TIMEOUT=30
CACHE_ENABLED=true
LOG_MAX_LINES=1000
VERIFY_INTEGRITY=true
AUTO_BACKUP=true
BACKUP_RETENTION=5
EOF
        chmod 600 "$config_file"
    fi
}

# List all available vaults
list_vaults() {
    echo -e "\n${BLUE}=== Available Vaults ===${NC}"
    
    if [[ ! -d "$vaults_dir" ]]; then
        echo -e "${YELLOW}No vaults directory found. Use 'Create New Vault' to get started.${NC}"
        return 1
    fi
    
    local vault_count=0
    local vault_num=1
    
    for vault_path in "$vaults_dir"/*; do
        if [[ -d "$vault_path" ]]; then
            local vault_name=$(basename "$vault_path")
            local vault_file="$vault_path/${CONFIG[VAULT_NAME]}"
            local server_count=0
            local status="Empty"
            
            # Get actual server count if vault exists and has content
            if [[ -f "$vault_file" ]]; then
                # Use safer file size checking
                local file_size=0
                if [[ -r "$vault_file" ]]; then
                    file_size=$(wc -c < "$vault_file" 2>/dev/null || echo 0)
                fi
                
                # Always attempt to decrypt if file exists (remove size threshold)
                if [[ $file_size -gt 0 ]]; then
                    # Vault has content, try to decrypt and count actual servers
                    local temp_file=$(create_svm_temp_file 'vault_count')
                    
                    # Try to decrypt with available passphrase
                    if [[ -n "$master_passphrase" ]]; then
                        local saved_passphrase="$passphrase"
                        passphrase="$master_passphrase"
                        
                        if decrypt_vault "$vault_file" "$temp_file" 2>/dev/null; then
                            # Count non-empty, non-comment lines
                            server_count=$(grep -v '^#' "$temp_file" 2>/dev/null | grep -v '^[[:space:]]*$' | wc -l || echo 0)
                            server_count=$(echo "$server_count" | tr -d ' ')
                            
                            if [[ $server_count -gt 0 ]]; then
                                status="Active"
                            else
                                status="Empty"
                            fi
                        else
                            # Decryption failed, use file size estimation as fallback
                            server_count=$((file_size / 150))
                            if [[ $server_count -gt 0 ]]; then
                                status="Encrypted"
                            else
                                status="Unknown"
                            fi
                        fi
                        
                        # Restore previous passphrase
                        passphrase="$saved_passphrase"
                        
                        # Clean up temp file
                        shred -zfu "$temp_file" 2>/dev/null || rm -f "$temp_file"
                    else
                        # No passphrase available, use file size estimation
                        server_count=$((file_size / 150))
                        if [[ $server_count -gt 0 ]]; then
                            status="Encrypted"
                        else
                            status="Unknown"
                        fi
                        rm -f "$temp_file"
                    fi
                else
                    status="Empty"
                fi
            fi
            
            # Show vault info
            printf "  %d. \033[0;35m%-20s\033[0m" "$vault_num" "$vault_name"
            
            if [[ "$status" == "Active" ]]; then
                printf " \033[0;32m[Active]\033[0m"
                printf " \033[0;36m(%d servers)\033[0m" "$server_count"
            elif [[ "$status" == "Encrypted" ]]; then
                printf " \033[0;93m[Encrypted]\033[0m"
                printf " \033[0;90m(~%d servers)\033[0m" "$server_count"
            elif [[ "$status" == "Unknown" ]]; then
                printf " \033[0;90m[Unknown]\033[0m"
                printf " \033[0;90m(~%d servers)\033[0m" "$server_count"
            else
                printf " \033[0;33m[Empty]\033[0m"
                printf " \033[0;37m(0 servers)\033[0m"
            fi
            
            # Show if it's the current vault
            if [[ "$vault_name" == "$current_vault_name" ]]; then
                printf " \033[0;34m← Current\033[0m"
            fi
            
            echo
            ((vault_count++))
            ((vault_num++))
        fi
    done
    
    if [[ $vault_count -eq 0 ]]; then
        echo -e "${YELLOW}No vaults found. Use 'Create New Vault' to get started.${NC}"
        return 1
    fi
    
    echo -e "\n${CYAN}Total vaults: $vault_count${NC}"
    return 0
}

# Create new vault
create_vault() {
    echo -e "\n${BLUE}=== Create New Vault ===${NC}"
    read -p "Enter vault name: " vault_name
    
    if [[ -z "$vault_name" ]]; then
        echo -e "${RED}Vault name cannot be empty.${NC}"
        return 1
    fi
    
    if [[ "$vault_name" =~ [^a-zA-Z0-9_-] ]]; then
        echo -e "${RED}Vault name can only contain letters, numbers, underscores, and hyphens.${NC}"
        return 1
    fi
    
    local vault_path="$vaults_dir/$vault_name"
    if [[ -d "$vault_path" ]]; then
        echo -e "${RED}Vault '$vault_name' already exists.${NC}"
        return 1
    fi
    
    # Create vault directory
    mkdir -p "$vault_path"
    chmod 700 "$vault_path"
    
    # Add to registry
    echo "$vault_name|$(date '+%Y-%m-%d %H:%M:%S')|$(whoami)" >> "$base_vault_dir/.vault_registry"
    
    # Set as current vault
    current_vault_name="$vault_name"
    vault="$vault_path"
    echo "$vault_name" > "$base_vault_dir/.current_vault"
    init_file_paths
    
    # Load and save default configuration for this vault
    load_config
    save_default_config
    
    # Create empty vault using master passphrase
    echo -e "${BLUE}Creating encrypted vault '$vault_name' with master passphrase...${NC}"
    
    # Use master passphrase for vault encryption
    passphrase="$master_passphrase"
    PASSPHRASE_TIMESTAMP=$(date +%s)
    
    # Create empty vault file
    touch "$tmp_servers_file"
    chmod 600 "$tmp_servers_file"
    
    # Encrypt and save the empty vault
    if encrypt_vault "$tmp_servers_file" "$servers_file"; then
        echo -e "${GREEN}Vault '$vault_name' created successfully and set as active.${NC}"
        log_event "VAULT_CREATED" "New vault created: $vault_name"
        return 0
    else
        echo -e "${RED}Failed to create vault.${NC}"
        # Cleanup on failure
        rm -rf "$vault_path"
        sed -i "/^$vault_name|/d" "$base_vault_dir/.vault_registry" 2>/dev/null
        rm -f "$base_vault_dir/.current_vault"
        current_vault_name=""
        vault=""
        return 1
    fi
}

# Select vault
select_vault() {
    echo -e "\n${BLUE}=== Select Vault ===${NC}"
    
    local vault_list=()
    local vault_paths=()
    local i=1
    
    for vault_path in "$vaults_dir"/*; do
        if [[ -d "$vault_path" ]]; then
            local vault_name=$(basename "$vault_path")
            
            # Count servers in each vault for display (using same logic as list_vaults)
            local vault_file="$vault_path/${CONFIG[VAULT_NAME]}"
            local server_count=0
            local status="Empty"
            
            if [[ -f "$vault_file" ]]; then
                local file_size=0
                if [[ -r "$vault_file" ]]; then
                    file_size=$(wc -c < "$vault_file" 2>/dev/null || echo 0)
                fi
                
                if [[ $file_size -gt 0 ]]; then
                    # Try to decrypt and count servers (remove size threshold)
                    if [[ -n "$master_passphrase" ]]; then
                        local temp_file=$(create_svm_temp_file 'select_count')
                        local saved_passphrase="$passphrase"
                        passphrase="$master_passphrase"
                        
                        if decrypt_vault "$vault_file" "$temp_file" 2>/dev/null; then
                            server_count=$(grep -v '^#' "$temp_file" 2>/dev/null | grep -v '^[[:space:]]*$' | wc -l || echo 0)
                            server_count=$(echo "$server_count" | tr -d ' ')
                            status="Active"
                        else
                            # Fallback to estimation
                            server_count=$((file_size / 150))
                            status="Encrypted"
                        fi
                        
                        passphrase="$saved_passphrase"
                        shred -zfu "$temp_file" 2>/dev/null || rm -f "$temp_file"
                    else
                        # No passphrase, use estimation
                        server_count=$((file_size / 150))
                        status="Encrypted"
                    fi
                fi
            fi

            # Show vault info with server count and current vault indicator
            printf "  %d. \033[0;35m%-20s\033[0m \033[0;36m(%d servers)\033[0m" "$i" "$vault_name" "$server_count"

            # Show if it's the current vault
            if [[ "$vault_name" == "$current_vault_name" ]]; then
                printf " \033[0;34m← Current\033[0m"
            fi
            
            echo
            
            vault_list+=("$vault_name")
            vault_paths+=("$vault_path")
            ((i++))
        fi
    done
    
    if [[ ${#vault_list[@]} -eq 0 ]]; then
        echo -e "${YELLOW}No vaults found. Create your first vault first.${NC}"
        return 1
    fi
    
    read -p "Enter vault number: " vault_num
    if ! [[ "$vault_num" =~ ^[0-9]+$ ]] || ((vault_num < 1)) || ((vault_num > ${#vault_list[@]})); then
        echo -e "${RED}Invalid selection.${NC}"
        return 1
    fi
    
    local selected_vault_name="${vault_list[$((vault_num-1))]}"
    local selected_vault_path="${vault_paths[$((vault_num-1))]}"
    
    # Set as current vault
    current_vault_name="$selected_vault_name"
    vault="$selected_vault_path"
    echo "$selected_vault_name" > "$base_vault_dir/.current_vault"
    init_file_paths
    
    echo -e "${GREEN}Vault '$selected_vault_name' selected successfully.${NC}"
    log_event "VAULT_SELECTED" "Vault selected: $selected_vault_name"
    
    return 0
}

# Delete vault
delete_vault() {
    echo -e "\n${BLUE}=== Delete Vault ===${NC}"
    
    local vault_list=()
    local vault_paths=()
    local i=1
    
    for vault_path in "$vaults_dir"/*; do
        if [[ -d "$vault_path" ]]; then
            local vault_name=$(basename "$vault_path")
            
            # Show vault info with indicator for current vault
            printf "  %d. \033[0;35m%-20s\033[0m" "$i" "$vault_name"
            
            # Show if it's the current vault
            if [[ "$vault_name" == "$current_vault_name" ]]; then
                printf " \033[0;34m← Current\033[0m"
            fi
            
            echo
            
            vault_list+=("$vault_name")
            vault_paths+=("$vault_path")
            ((i++))
        fi
    done
    
    if [[ ${#vault_list[@]} -eq 0 ]]; then
        echo -e "${YELLOW}No vaults found to delete.${NC}"
        return 1
    fi
    
    # Give 3 attempts to enter a valid vault number
    local vault_num_attempts=0
    local max_vault_num_attempts=3
    local vault_num
    local valid_vault_num=false
    
    # Temporarily disable exit on error to prevent premature exits
    local original_e
    if [[ $- == *e* ]]; then
        set +e
        original_e=true
    fi
    
    while [[ $vault_num_attempts -lt $max_vault_num_attempts ]]; do
        # Use a more robust read command that handles signals better
        if ! read -p "Enter vault number to delete (attempt $((vault_num_attempts + 1))/$max_vault_num_attempts): " vault_num; then
            echo -e "\n${YELLOW}Input cancelled. Returning to vault management menu.${NC}"
            # Restore original error handling
            [[ "$original_e" == "true" ]] && set -e
            return 0
        fi
        
        if [[ "$vault_num" =~ ^[0-9]+$ ]] && ((vault_num >= 1)) && ((vault_num <= ${#vault_list[@]})); then
            valid_vault_num=true
            break
        else
            ((vault_num_attempts++))
            if [[ $vault_num_attempts -lt $max_vault_num_attempts ]]; then
                echo -e "${RED}Invalid selection. Please try again.${NC}"
            else
                echo -e "${YELLOW}Maximum attempts reached. Returning to vault management menu.${NC}"
                # Restore original error handling
                [[ "$original_e" == "true" ]] && set -e
                return 0
            fi
        fi
    done
    
    # Restore original error handling
    [[ "$original_e" == "true" ]] && set -e
    
    if [[ "$valid_vault_num" != "true" ]]; then
        return 0
    fi
    
    local vault_to_delete="${vault_list[$((vault_num-1))]}"
    local vault_to_delete_path="${vault_paths[$((vault_num-1))]}"
    
    echo -e "${YELLOW}Warning: This will permanently delete vault '$vault_to_delete' and all its data.${NC}"
    
    local attempts=0
    local max_attempts=3
    local confirmation_successful=false
    
    # Temporarily disable exit on error to prevent premature exits
    local original_e_confirmation
    if [[ $- == *e* ]]; then
        set +e
        original_e_confirmation=true
    fi
    
    while [[ $attempts -lt $max_attempts ]]; do
        # Use a more robust read command that handles signals better
        if ! read -p "Are you sure? Type the vault name '$vault_to_delete' to confirm (attempt $((attempts + 1))/$max_attempts): " confirmation; then
            echo -e "\n${YELLOW}Input cancelled. Deletion cancelled.${NC}"
            # Restore original error handling
            [[ "$original_e_confirmation" == "true" ]] && set -e
            return 0
        fi
        
        if [[ "$confirmation" == "$vault_to_delete" ]]; then
            confirmation_successful=true
            break
        else
            ((attempts++))
            if [[ $attempts -lt $max_attempts ]]; then
                echo -e "${RED}Incorrect vault name. Please try again.${NC}"
            else
                echo -e "${YELLOW}Maximum attempts reached. Deletion cancelled.${NC}"
                # Restore original error handling
                [[ "$original_e_confirmation" == "true" ]] && set -e
                return 0
            fi
        fi
    done
    
    # Restore original error handling
    [[ "$original_e_confirmation" == "true" ]] && set -e
    
    # Check if confirmation was successful
    if [[ "$confirmation_successful" == "true" ]]; then
        echo -e "${GREEN}Confirmation successful. Proceeding with deletion...${NC}"
    else
        echo -e "${YELLOW}Deletion cancelled.${NC}"
        return 0
    fi
    
    # Create backup before deletion
    local backup_file="$base_vault_dir/${vault_to_delete}_backup_$(date +%Y%m%d_%H%M%S).enc"
    local vault_servers_file="$vault_to_delete_path/${CONFIG[VAULT_NAME]}"
    if [[ -f "$vault_servers_file" ]]; then
        cp "$vault_servers_file" "$backup_file"
        echo -e "${YELLOW}Backup created: $backup_file${NC}"
    fi
    
    # Remove from registry
    sed -i "/^$vault_to_delete|/d" "$base_vault_dir/.vault_registry" 2>/dev/null
    
    # Delete vault directory
    rm -rf "$vault_to_delete_path"
    
    # Clear current vault if it was the deleted one
    if [[ "$vault_to_delete" == "$current_vault_name" ]]; then
        rm -f "$base_vault_dir/.current_vault"
        current_vault_name=""
        vault=""
        servers_file=""
        config_file=""
        log_file=""
        echo -e "${YELLOW}Current vault was deleted. Please select a new vault.${NC}"
    fi
    
    echo -e "${GREEN}Vault '$vault_to_delete' deleted successfully.${NC}"
    log_event "VAULT_DELETED" "Vault deleted: $vault_to_delete"
    
    # Ask user if they want to return to menu or exit
    echo -e "\n${CYAN}=== Post-Deletion Options ===${NC}"
    echo -e "${YELLOW}Vault deletion completed successfully.${NC}"
    echo
    echo "1. Return to Vault Management Menu"
    echo "2. Exit SSH Vault Manager"
    echo
    read -p "Enter your choice (1 or 2): " post_delete_choice
    
    case $post_delete_choice in
        1)
            echo -e "${BLUE}Returning to vault management menu...${NC}"
            return 0
            ;;
        2)
            echo -e "${BLUE}Exiting SSH Vault Manager...${NC}"
            cleanup
            ;;
        *)
            echo -e "${YELLOW}Invalid choice. Returning to vault management menu...${NC}"
            return 0
            ;;
    esac
}

# Rename vault
rename_vault() {
    echo -e "\n${BLUE}=== Rename Vault ===${NC}"
    
    if [[ -z "$current_vault_name" ]]; then
        echo -e "${RED}No vault selected. Please select a vault first.${NC}"
        return 1
    fi
    
    read -p "Enter new vault name: " new_vault_name
    
    if [[ -z "$new_vault_name" ]]; then
        echo -e "${RED}Vault name cannot be empty.${NC}"
        return 1
    fi
    
    if [[ "$new_vault_name" =~ [^a-zA-Z0-9_-] ]]; then
        echo -e "${RED}Vault name can only contain letters, numbers, underscores, and hyphens.${NC}"
        return 1
    fi
    
    local new_vault_path="$vaults_dir/$new_vault_name"
    if [[ -d "$new_vault_path" ]]; then
        echo -e "${RED}Vault '$new_vault_name' already exists.${NC}"
        return 1
    fi
    
    # Rename directory
    mv "$vault" "$new_vault_path"
    
    # Update registry
    sed -i "s/^$current_vault_name|/$new_vault_name|/" "$base_vault_dir/.vault_registry" 2>/dev/null
    
    # Update current vault reference
    current_vault_name="$new_vault_name"
    vault="$new_vault_path"
    echo "$new_vault_name" > "$base_vault_dir/.current_vault"
    init_file_paths
    
    echo -e "${GREEN}Vault renamed from '$current_vault_name' to '$new_vault_name' successfully.${NC}"
    log_event "VAULT_RENAMED" "Vault renamed: $current_vault_name -> $new_vault_name"
    
    return 0
}

# Show vault information
show_vault_info() {
    echo -e "\n${BLUE}=== Vault Information ===${NC}"

    # List all vaults and prompt for selection
    if [[ ! -d "$vaults_dir" ]]; then
        echo -e "${YELLOW}No vaults directory found. Use 'Create New Vault' to get started.${NC}"
        return 1
    fi

    local vault_list=()
    local vault_paths=()
    local i=1
    for vault_path in "$vaults_dir"/*; do
        if [[ -d "$vault_path" ]]; then
            local vault_name=$(basename "$vault_path")
            vault_list+=("$vault_name")
            vault_paths+=("$vault_path")
            echo "  $i. $vault_name"
            ((i++))
        fi
    done

    if [[ ${#vault_list[@]} -eq 0 ]]; then
        echo -e "${YELLOW}No vaults found. Use 'Create New Vault' to get started.${NC}"
        return 1
    fi

    local selected_vault_name
    local selected_vault_path
    if [[ ${#vault_list[@]} -eq 1 ]]; then
        selected_vault_name="${vault_list[0]}"
        selected_vault_path="${vault_paths[0]}"
        echo -e "${YELLOW}Only one vault found. Showing info for: $selected_vault_name${NC}"
    else
        read -p "Enter vault number to view info: " vault_num
        if ! [[ "$vault_num" =~ ^[0-9]+$ ]] || ((vault_num < 1)) || ((vault_num > ${#vault_list[@]})); then
            echo -e "${RED}Invalid selection.${NC}"
            return 1
        fi
        selected_vault_name="${vault_list[$((vault_num-1))]}"
        selected_vault_path="${vault_paths[$((vault_num-1))]}"
    fi

    local vault_file="$selected_vault_path/${CONFIG[VAULT_NAME]}"
    local config_file="$selected_vault_path/${CONFIG[CONFIG_NAME]}"
    local log_file="$selected_vault_path/${CONFIG[LOG_NAME]}"

    echo -e "${CYAN}Vault Name:${NC} $selected_vault_name"
    echo -e "${CYAN}Vault Path:${NC} $selected_vault_path"
    echo -e "${CYAN}Created:${NC} $(stat -c %y "$selected_vault_path" 2>/dev/null | cut -d' ' -f1 || echo 'Unknown')"

    if [[ -f "$vault_file" ]]; then
        local file_size=$(stat -c %s "$vault_file" 2>/dev/null || echo "0")
        echo -e "${CYAN}Vault File Size:${NC} $file_size bytes"
        # Try to decrypt and count servers
        local temp_file=$(create_svm_temp_file 'info')
        passphrase="$master_passphrase"
        if decrypt_vault "$vault_file" "$temp_file" 2>/dev/null; then
            local server_count=$(wc -l < "$temp_file" 2>/dev/null | tr -d ' ')
            server_count=${server_count:-0}
            echo -e "${CYAN}Server Count:${NC} $server_count"
        else
            echo -e "${CYAN}Server Count:${NC} Unable to decrypt"
        fi
        shred -zfu "$temp_file" 2>/dev/null
    else
        echo -e "${CYAN}Vault File:${NC} Not found"
        echo -e "${CYAN}Server Count:${NC} 0"
    fi

    if [[ -f "$config_file" ]]; then
        local config_count=$(grep -c "=" "$config_file" 2>/dev/null || echo "0")
        echo -e "${CYAN}Configuration:${NC} Loaded ($config_count settings)"
    else
        echo -e "${CYAN}Configuration:${NC} Using defaults"
    fi

    if [[ -f "$log_file" ]]; then
        local log_size=$(stat -c %s "$log_file" 2>/dev/null || echo "0")
        echo -e "${CYAN}Log File Size:${NC} $log_size bytes"
    else
        echo -e "${CYAN}Log File:${NC} Not found"
    fi

    return 0
}

# Auto-create default vault during runtime if none exists and user wants to add a server
auto_create_default_vault() {
    local default_vault_name="default"
    local default_vault_path="$vaults_dir/$default_vault_name"
    
    echo -e "${BLUE}No vault is currently selected.${NC}"
    echo -e "${YELLOW}Creating a default vault for you...${NC}"
    
    # Create the default vault directory
    mkdir -p "$default_vault_path"
    chmod 700 "$default_vault_path"
    
    # Add to vault registry
    echo "$default_vault_name|$(date '+%Y-%m-%d %H:%M:%S')|$(whoami)" >> "$base_vault_dir/.vault_registry"
    
    # Set as current vault
    current_vault_name="$default_vault_name"
    vault="$default_vault_path"
    echo "$default_vault_name" > "$base_vault_dir/.current_vault"
    chmod 600 "$base_vault_dir/.current_vault"
    
    # Initialize file paths
    init_file_paths
    
    # Create and load default configuration
    save_default_config
    load_config
    
    # Create empty vault file using master passphrase
    passphrase="$master_passphrase"
    PASSPHRASE_TIMESTAMP=$(date +%s)
    
    # Create empty vault file
    touch "$tmp_servers_file"
    chmod 600 "$tmp_servers_file"
    
    # Encrypt and save the empty vault
    if encrypt_vault "$tmp_servers_file" "$servers_file"; then
        echo -e "${GREEN}✅ Default vault '$default_vault_name' created and activated.${NC}"
        log_event "VAULT_AUTO_CREATED" "Default vault auto-created: $default_vault_name"
        return 0
    else
        echo -e "${RED}Failed to create default vault.${NC}"
        return 1
    fi
}

# Search all vaults for a server name (case-insensitive) and connect automatically
search_all_vaults() {
    local search_term="$1"
    local search_lc="${search_term,,}"    # lowercase for matching
    local found_any=false
    local found_servers=()
    local found_vaults=()

    echo -e "\n${BLUE}=== Global Search: '$search_term' Across All Vaults ===${NC}"

    [[ ! -d "$vaults_dir" ]] && {
        echo -e "${RED}No vaults directory found.${NC}"
        return 1
    }

    # ── Make sure decrypt_vault has the passphrase it needs ─────────────────────
    passphrase="$master_passphrase"

    # ── Scan each vault directory ───────────────────────────────────────────────
    for vault_path in "$vaults_dir"/*; do
        [[ ! -d "$vault_path" ]] && continue
        local vault_name=$(basename "$vault_path")
        local vault_file="$vault_path/${CONFIG[VAULT_NAME]}"
        [[ ! -f "$vault_file" ]] && continue

        # decrypt to temp
        local tmp_file
        tmp_file=$(create_svm_temp_file 'search')
        if ! decrypt_vault "$vault_file" "$tmp_file" >/dev/null 2>&1; then
            rm -f "$tmp_file"
            continue
        fi

        # collect any matching lines
        while IFS= read -r line; do
            [[ -z "$line" || "$line" =~ ^# ]] && continue
            IFS='|' read -r name ip username password port group info <<< "$line"
            if [[ "${name,,}" == *"$search_lc"* ]]; then
                found_any=true
                found_servers+=("$line")
                found_vaults+=("$vault_name")
            fi
        done < "$tmp_file"
        rm -f "$tmp_file"
    done

    # ── No matches? ─────────────────────────────────────────────────────────────
    if ! $found_any; then
        echo -e "${YELLOW}No servers matching '$search_term' found in any vault.${NC}"
        return 1
    fi

    # ── Single match → SSH immediately ─────────────────────────────────────────
    if (( ${#found_servers[@]} == 1 )); then
        IFS='|' read -r name ip username password port group info <<< "${found_servers[0]}"
        vault_name="${found_vaults[0]}"

        echo -e "\n${BLUE}Connecting to ${GREEN}$name${BLUE} (${GREEN}$ip${BLUE}) in vault '${GREEN}$vault_name${BLUE}'…${NC}"
        STATS[connections_attempted]=$((STATS[connections_attempted]+1))
        log_event "CONNECTION_ATTEMPT" "Global search → $name ($ip)" "$name|$ip"

        if command -v sshpass &>/dev/null; then
            sshpass -p "$password" ssh -o StrictHostKeyChecking=no -p "$port" "$username@$ip"
        else
            ssh -p "$port" "$username@$ip"
        fi
        return $?
    fi

    # ── Multiple matches → draw dynamic table ──────────────────────────────────
    echo -e "\n${CYAN}=== Search Results ===${NC}"
    echo -e "${BLUE}Found ${GREEN}${#found_servers[@]}${BLUE} matching servers:${NC}\n"

    # dynamic Vault-column width
    local vault_header="Vault"
    local max_v_len=${#vault_header}
    for vn in "${found_vaults[@]}"; do
        (( ${#vn} > max_v_len )) && max_v_len=${#vn}
    done
    local vcol_w=$max_v_len

    # fixed widths for other columns
    local c1=3 c2=15 c3=17 c4=12
    local d1=$((c1+2)) d2=$((c2+2)) d3=$((c3+2)) d4=$((c4+2)) d5=$((vcol_w+2))
    local b1 b2 b3 b4 b5
    b1=$(printf '─%.0s' $(seq 1 $d1))
    b2=$(printf '─%.0s' $(seq 1 $d2))
    b3=$(printf '─%.0s' $(seq 1 $d3))
    b4=$(printf '─%.0s' $(seq 1 $d4))
    b5=$(printf '─%.0s' $(seq 1 $d5))

    # header row
    echo -e "${CYAN}┌${b1}┬${b2}┬${b3}┬${b4}┬${b5}┐${NC}"
    printf "${CYAN}│ ${YELLOW}%-3s${CYAN} │ ${YELLOW}%-15s${CYAN} │ ${YELLOW}%-17s${CYAN} │ ${YELLOW}%-12s${CYAN} │ ${YELLOW}%-*s${CYAN} │${NC}\n" \
        "#" "Name" "IP Address" "Username" "$vcol_w" "$vault_header"
    echo -e "${CYAN}├${b1//?/─}┼${b2//?/─}┼${b3//?/─}┼${b4//?/─}┼${b5//?/─}┤${NC}"

    # data rows (alternating)
    for i in "${!found_servers[@]}"; do
        IFS='|' read -r name ip username password port group info <<< "${found_servers[$i]}"
        local vault_disp="${found_vaults[$i]:0:vcol_w}"
        if (( i % 2 == 0 )); then
            printf "${CYAN}│ ${GREEN}%-3s${CYAN} │ ${GREEN}%-15s${CYAN} │ ${GREEN}%-17s${CYAN} │ ${GREEN}%-12s${CYAN} │ ${GREEN}%-*s${CYAN} │${NC}\n" \
                $((i+1)) "$name" "$ip" "$username" "$vcol_w" "$vault_disp"
        else
            printf "${CYAN}│ ${CYAN}%-3s${CYAN} │ ${CYAN}%-15s${CYAN} │ ${CYAN}%-17s${CYAN} │ ${CYAN}%-12s${CYAN} │ ${CYAN}%-*s${CYAN} │${NC}\n" \
                $((i+1)) "$name" "$ip" "$username" "$vcol_w" "$vault_disp"
        fi
    done

    # bottom border
    echo -e "${CYAN}└${b1}┴${b2}┴${b3}┴${b4}┴${b5}┘${NC}"

    # prompt for selection
    echo -e "\n${YELLOW}💡 Select a server number to connect:${NC}"
    read -p "Enter server number: " selection
    if ! [[ "$selection" =~ ^[0-9]+$ ]] || (( selection < 1 || selection > ${#found_servers[@]} )); then
        echo -e "${RED}❌ Invalid selection.${NC}"
        return 1
    fi

    # SSH to the chosen server
    local idx=$((selection-1))
    IFS='|' read -r name ip username password port group info <<< "${found_servers[$idx]}"
    vault_name="${found_vaults[$idx]}"

    echo -e "\n${BLUE}Connecting to ${GREEN}$name${BLUE} (${GREEN}$ip${BLUE}) in vault '${GREEN}$vault_name${BLUE}'…${NC}"
    STATS[connections_attempted]=$((STATS[connections_attempted]+1))
    log_event "CONNECTION_ATTEMPT" "User selected $name ($ip)" "$name|$ip"

    if command -v sshpass &>/dev/null; then
        sshpass -p "$password" ssh -o StrictHostKeyChecking=no -p "$port" "$username@$ip"
    else
        ssh -p "$port" "$username@$ip"
    fi

    cleanup
    exit 0
}
