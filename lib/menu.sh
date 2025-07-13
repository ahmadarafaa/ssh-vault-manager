#!/bin/bash

# ============================================================================
# MENU MODULE
# ============================================================================

# Ensure SVM_LAUNCH_DIR is set
: "${SVM_LAUNCH_DIR:=$PWD}"

# Add these at the top of the file, before any function definitions
print_separator() {
    printf "+"
    for ((i=0; i<col_count; i++)); do
        printf '%s' "$(printf '%0.s-' $(seq 1 $((col_widths[$i]+2))))+"
    done
    printf "\n"
}
print_row() {
    if [[ -z "$1" ]]; then
        echo "[DEBUG] print_row called with empty argument, skipping" >&2
        return
    fi
    IFS='|' read -r -a fields <<< "$1"
    printf "|"
    for ((i=0; i<col_count; i++)); do
        printf " %-*s |" "${col_widths[$i]}" "${fields[$i]}"
    done
    printf "\n"
}

# Beautiful prompt function
get_beautiful_prompt() {
    if [[ -n "$current_vault_name" ]]; then
        echo -e "${CYAN}╭─ ${GREEN}🔐 Vault: ${YELLOW}$current_vault_name${NC} ${CYAN}─╮${NC}\n${CYAN}╰─ ${BLUE}Enter your choice: ${NC}"
    else
        echo -e "${CYAN}╭─ ${YELLOW}⚠️  No vault selected${NC} ${CYAN}─╮${NC}\n${CYAN}╰─ ${BLUE}Enter your choice: ${NC}"
    fi
}

# Main menu
show_menu() {
    local show_menu_header=true
    session_active=true
    while true; do
        if [[ "$show_menu_header" == "true" ]]; then
            echo -e "\n${BLUE}=== SSH Vault Manager ===${NC}"
            if [[ -n "$current_vault_name" ]]; then
                echo -e "${CYAN}Active Vault: ${GREEN}$current_vault_name${NC}"
                echo
            fi
            echo -e "${MAGENTA}V. Vault Management${NC}"
            echo "1. Connect to Server"
            echo "2. Add Server"
            echo "3. Remove Server"
            echo "4. Modify Server"
            echo "5. List Servers"
            echo "6. Search Servers (Current Vault)"
            echo "7. Global Search (All Vaults)"
            echo "8. View Connection Logs & Statistics"
            echo "9. Verify Vault Integrity"
            echo "10. Show Configuration"
            echo "0. Quit"
            echo -e "${YELLOW}c. Clear Screen${NC}"
            echo -e "${YELLOW}s. Show Statistics${NC}"
            echo -e "${YELLOW}h. Health Check${NC}"
        fi
        show_menu_header=true
        read -p "$(get_beautiful_prompt)" choice
        case $choice in
            [vV]) show_vault_menu ;;
            1) if [[ -z "$current_vault_name" ]]; then echo -e "${RED}No vault selected. Please use 'V' to select a vault first.${NC}"; continue_or_exit; else prompt_passphrase && check_file && connect; fi ;;
            2) if [[ -z "$current_vault_name" ]]; then if auto_create_default_vault; then prompt_passphrase && check_file && add_server && save_vault; continue_or_exit; else echo -e "${RED}Failed to create default vault. Please use 'V' to create a vault manually.${NC}"; continue_or_exit; fi; else prompt_passphrase && check_file && add_server && save_vault; continue_or_exit; fi ;;
            3) if [[ -z "$current_vault_name" ]]; then echo -e "${RED}No vault selected. Please use 'V' to select a vault first.${NC}"; continue_or_exit; else prompt_passphrase && check_file && remove_server && save_vault; continue_or_exit; fi ;;
            4) if [[ -z "$current_vault_name" ]]; then echo -e "${RED}No vault selected. Please use 'V' to select a vault first.${NC}"; continue_or_exit; else prompt_passphrase && check_file && modify_server && save_vault; continue_or_exit; fi ;;
            5) if [[ -z "$current_vault_name" ]]; then echo -e "${RED}No vault selected. Please use 'V' to select a vault first.${NC}"; continue_or_exit; else prompt_passphrase && check_file && list_servers && continue_or_exit; fi ;;
            6) if [[ -z "$current_vault_name" ]]; then echo -e "${RED}No vault selected. Please use 'V' to select a vault first.${NC}"; continue_or_exit; else prompt_passphrase && check_file && search_servers; continue_or_exit; fi ;;
            7) prompt_passphrase; read -p "Enter search term for global search: " search_term; if [[ -z "$search_term" ]]; then echo -e "${YELLOW}Search term cannot be empty.${NC}"; continue_or_exit; else search_all_vaults "$search_term"; continue_or_exit; fi ;;
            8) view_logs; continue_or_exit ;;
            9) if [[ -z "$current_vault_name" ]]; then echo -e "${RED}No vault selected. Please use 'V' to select a vault first.${NC}"; continue_or_exit; else prompt_passphrase && check_file && echo -e "${GREEN}Vault integrity verified successfully.${NC}"; continue_or_exit; fi ;;
            10) echo -e "\n${BLUE}=== Current Configuration ===${NC}"; for key in "${!CONFIG[@]}"; do echo -e "${CYAN}$key${NC}: ${CONFIG[$key]}"; done; continue_or_exit ;;
            0|[qQ]) cleanup ;;
            [cC]) clear; banner ;;
            [sS]) show_statistics; continue_or_exit ;;
            [hH]) echo -e "\n${BLUE}=== System Health Check ===${NC}"; echo -e "${GREEN}✓${NC} Base directory: $base_vault_dir"; echo -e "${GREEN}✓${NC} Vaults directory: $vaults_dir"; echo -e "${GREEN}✓${NC} Configuration loaded: ${#CONFIG[@]} settings"; echo -e "${GREEN}✓${NC} Session active: $session_active"; if [[ -n "$current_vault_name" ]]; then echo -e "${GREEN}✓${NC} Current vault: $current_vault_name"; [[ -f "$servers_file" ]] && echo -e "${GREEN}✓${NC} Vault file exists" || echo -e "${YELLOW}!${NC} No vault file"; else echo -e "${YELLOW}!${NC} No vault selected"; fi; local vault_count=$(ls -1d "$vaults_dir"/* 2>/dev/null | wc -l); echo -e "${GREEN}✓${NC} Total vaults: $vault_count"; continue_or_exit ;;
            *) echo -e "${RED}Invalid choice. Please try again.${NC}"; show_menu_header=false ;;
        esac
    done
}

# Add export_vault function
export_vault() {
    if [[ -z "$current_vault_name" ]]; then
        echo -e "${RED}No vault selected. Please use 'V' to select a vault first.${NC}"
        return
    fi
    if [[ ! -f "$servers_file" ]]; then
        echo -e "${RED}No vault file found to export.${NC}"
        return
    fi
    echo -e "\n${BLUE}=== Export Vault: $current_vault_name ===${NC}"
    echo "1. Export as encrypted file (with new password)"
    echo "2. Export as plain text (decrypted)"
    read -p "Choose export type [1]: " export_type
    export_type="${export_type:-1}"
    local default_dest
    local export_dest
    local temp_file

    if [[ "$export_type" == "2" ]]; then
        temp_file="$(create_svm_temp_file 'export')"
        passphrase="$master_passphrase"
        if ! decrypt_vault "$servers_file" "$temp_file"; then
            echo -e "${RED}Failed to decrypt vault for export.${NC}"
            shred -zfu "$temp_file" 2>/dev/null
            continue_or_exit
            return
        fi
        # Remove all debug lines and od -c from the plain text export path
        # Only keep user-facing messages and export logic
        vault_lines=("Name|IP|Username|Password|Port|Group|AdditionalInfo")
        while IFS= read -r line || [[ -n $line ]]; do
            vault_lines+=("$line")
        done < "$temp_file"
        IFS='|' read -r -a headers <<< "${vault_lines[0]}"
        col_count=${#headers[@]}
        col_widths=()
        for ((i=0; i<col_count; i++)); do
            col_widths[$i]=${#headers[$i]}
        done
        for line in "${vault_lines[@]}"; do
            IFS='|' read -r -a fields <<< "$line"
            for ((i=0; i<col_count; i++)); do
                [[ ${#fields[$i]} -gt ${col_widths[$i]} ]] && col_widths[$i]=${#fields[$i]}
            done
        done
        # Set default export directory and prompt for destination
        export_dir="$HOME/.svm/exported-vaults"
        mkdir -p "$export_dir"
        default_dest="$export_dir/${current_vault_name}_vault_export_$(date +%Y%m%d_%H%M%S).txt"
        read -e -p "Enter export destination [${default_dest}]: " export_dest
        if [[ -z "$export_dest" ]]; then
            export_dest="$default_dest"
        elif [[ "$export_dest" == /* || "$export_dest" == ~* ]]; then
            export_dest="$(realpath -m -- "$export_dest")"
        else
            export_dest="$(realpath -m -- "$SVM_LAUNCH_DIR/$export_dest")"
        fi
        if [[ -z "$export_dest" ]]; then
          echo "[ERROR] export_dest is empty! Aborting export." >&2
          return 1
        fi
        {
          true
          print_separator
          print_row "${vault_lines[0]}"
          print_separator
          for ((row=1; row<${#vault_lines[@]}; row++)); do
            print_row "${vault_lines[$row]}"
          done
          print_separator
        } > "$export_dest"
        if [[ $? -eq 0 ]]; then
            echo -e "${GREEN}Vault exported (plain text) successfully to: $export_dest${NC}"
        else
            echo -e "${RED}Failed to export vault as plain text.${NC}"
        fi
        shred -zfu "$temp_file" 2>/dev/null
        return
    else
        # Export as encrypted file with new password
        local export_pass1 export_pass2
        local max_attempts=3
        local attempt=1
        while (( attempt <= max_attempts )); do
            read -s -p "[$attempt/$max_attempts] Enter a password for the exported encrypted file: " export_pass1; echo
            read -s -p "[$attempt/$max_attempts] Confirm password: " export_pass2; echo
            if [[ "$export_pass1" != "$export_pass2" ]]; then
                echo -e "${RED}Passwords do not match. Try again.${NC}"
            elif [[ -z "$export_pass1" ]]; then
                echo -e "${RED}Password cannot be empty. Try again.${NC}"
            else
                break
            fi
            ((attempt++))
        done
        if (( attempt > max_attempts )); then
            echo -e "${RED}Maximum password attempts exceeded. Export aborted.${NC}"
            return
        fi
        temp_file="$(create_svm_temp_file 'export')"
        passphrase="$master_passphrase"
        if ! decrypt_vault "$servers_file" "$temp_file"; then
            echo -e "${RED}Failed to decrypt vault for export.${NC}"
            shred -zfu "$temp_file" 2>/dev/null
            return
        fi
        # Set default export directory and prompt for destination
        export_dir="$HOME/.svm/exported-vaults"
        mkdir -p "$export_dir"
        default_dest="$export_dir/${current_vault_name}_vault_export_$(date +%Y%m%d_%H%M%S).enc"
        read -e -p "Enter export destination [${default_dest}]: " export_dest
        if [[ -z "$export_dest" ]]; then
            export_dest="$default_dest"
        elif [[ "$export_dest" == /* || "$export_dest" == ~* ]]; then
            export_dest="$(realpath -m -- "$export_dest")"
        else
            export_dest="$(realpath -m -- "$SVM_LAUNCH_DIR/$export_dest")"
        fi
        passphrase="$export_pass1"
        if encrypt_vault "$temp_file" "$export_dest"; then
            echo -e "${GREEN}Vault exported (encrypted) successfully to: $export_dest${NC}"
        else
            echo -e "${RED}Failed to export encrypted vault.${NC}"
        fi
        shred -zfu "$temp_file" 2>/dev/null
        return
    fi
}

# Add import_vault function
import_vault() {
    echo -e "\n${BLUE}=== Import Vault ===${NC}"
    echo "1. Import from encrypted file"
    echo "2. Import from plain text file"
    read -p "Choose import type [1]: " import_type
    import_type="${import_type:-1}"
    
    local import_file
    local temp_file
    local vault_name
    
    # Prompt for import file
    read -e -p "Enter path to import file: " import_file
    if [[ -z "$import_file" ]]; then
        echo -e "${RED}Import file path cannot be empty.${NC}"
        return
    fi
    
    # Resolve the import file path
    if [[ "$import_file" == /* || "$import_file" == ~* ]]; then
        import_file="$(realpath -m -- "$import_file")"
    else
        import_file="$(realpath -m -- "$SVM_LAUNCH_DIR/$import_file")"
    fi
    
    # Check if file exists
    if [[ ! -f "$import_file" ]]; then
        echo -e "${RED}Import file not found: $import_file${NC}"
        return
    fi
    
    # Prompt for vault name
    read -p "Enter vault name for import: " vault_name
    if [[ -z "$vault_name" ]]; then
        echo -e "${RED}Vault name cannot be empty.${NC}"
        return
    fi
    
    # Check if vault already exists
    local vault_dir="$vaults_dir/$vault_name"
    if [[ -d "$vault_dir" ]]; then
        echo -e "${YELLOW}Warning: Vault '$vault_name' already exists.${NC}"
        read -p "Do you want to overwrite it? (y/N): " overwrite
        if [[ ! "$overwrite" =~ ^[Yy]$ ]]; then
            echo -e "${YELLOW}Import cancelled.${NC}"
            return
        fi
    fi
    
    # Create vault directory
    mkdir -p "$vault_dir"
    
    if [[ "$import_type" == "1" ]]; then
        # Import from encrypted file
        echo -e "\n${BLUE}=== Import from Encrypted File ===${NC}"
        
        # Prompt for password
        local import_pass
        read -s -p "Enter password for the encrypted file: " import_pass; echo
        
        if [[ -z "$import_pass" ]]; then
            echo -e "${RED}Password cannot be empty.${NC}"
            return
        fi
        
        # Create temporary file for decryption
        temp_file="$(create_svm_temp_file 'import')"
        
        # Try to decrypt the import file
        passphrase="$import_pass"
        if ! decrypt_vault "$import_file" "$temp_file"; then
            echo -e "${RED}Failed to decrypt import file. Check the password.${NC}"
            shred -zfu "$temp_file" 2>/dev/null
            return
        fi
        
        # Validate the decrypted content
        if ! validate_vault_format "$temp_file"; then
            echo -e "${RED}Invalid vault format in decrypted import file.${NC}"
            shred -zfu "$temp_file" 2>/dev/null
            return
        fi
        
        # Encrypt with current master passphrase
        local vault_file="$vault_dir/.vault.enc"
        passphrase="$master_passphrase"
        if encrypt_vault "$temp_file" "$vault_file"; then
            echo -e "${GREEN}Vault imported successfully to: $vault_name${NC}"
            # Register vault in registry
            echo "$vault_name|$(date '+%Y-%m-%d %H:%M:%S')|$(whoami)" >> "$base_vault_dir/.vault_registry"
            # Set as current vault
            current_vault_name="$vault_name"
            vault="$vault_dir"
            echo "$vault_name" > "$base_vault_dir/.current_vault"
            init_file_paths
        else
            echo -e "${RED}Failed to import vault.${NC}"
        fi
        
        shred -zfu "$temp_file" 2>/dev/null
        
    else
        # Import from plain text file
        echo -e "\n${BLUE}=== Import from Plain Text File ===${NC}"
        
        # Check if it's beautified table format
        local first_line
        read -r first_line < "$import_file"
        local temp_converted_file
        local final_import_file="$import_file"
        
        if [[ "$first_line" =~ ^\+.*\+$ ]]; then
            # Convert beautified table to raw format
            temp_converted_file="$(create_svm_temp_file 'convert')"
            if convert_table_to_raw "$import_file" "$temp_converted_file"; then
                final_import_file="$temp_converted_file"
            else
                echo -e "${RED}Failed to convert table format.${NC}"
                [[ -f "$temp_converted_file" ]] && shred -zfu "$temp_converted_file" 2>/dev/null
                return
            fi
        fi
        
        # Validate the plain text format
        if ! validate_vault_format "$final_import_file"; then
            echo -e "${RED}Invalid vault format in import file.${NC}"
            [[ -f "$temp_converted_file" ]] && shred -zfu "$temp_converted_file" 2>/dev/null
            return
        fi
        
        # Create a clean temporary file without the header line
        local clean_import_file="$(create_svm_temp_file 'clean')"
        
        # Skip the first line (header) when importing
        tail -n +2 "$final_import_file" > "$clean_import_file"
        
        # Encrypt with current master passphrase
        local vault_file="$vault_dir/.vault.enc"
        passphrase="$master_passphrase"
        if encrypt_vault "$clean_import_file" "$vault_file"; then
            echo -e "${GREEN}Vault imported successfully to: $vault_name${NC}"
            # Register vault in registry
            echo "$vault_name|$(date '+%Y-%m-%d %H:%M:%S')|$(whoami)" >> "$base_vault_dir/.vault_registry"
            # Set as current vault
            current_vault_name="$vault_name"
            vault="$vault_dir"
            echo "$vault_name" > "$base_vault_dir/.current_vault"
            init_file_paths
        else
            echo -e "${RED}Failed to import vault.${NC}"
        fi
        
        # Clean up temporary files
        [[ -f "$temp_converted_file" ]] && shred -zfu "$temp_converted_file" 2>/dev/null
        [[ -f "$clean_import_file" ]] && shred -zfu "$clean_import_file" 2>/dev/null
    fi
    
    return
}

# Helper function to validate vault format
validate_vault_format() {
    local file="$1"
    local first_line
    
    # Check if file exists and is readable
    if [[ ! -r "$file" ]]; then
        return 1
    fi
    
    # Read first line
    read -r first_line < "$file"
    
    # Check if it's a valid header (contains pipe-separated fields)
    # The format should be: Name|IP|Username|Password|Port|Group|AdditionalInfo
    if [[ "$first_line" == "Name|IP|Username|Password|Port|Group|AdditionalInfo" ]]; then
        return 0
    fi
    
    # Check if it contains pipe-separated values (at least 5 fields)
    local pipe_count=$(echo "$first_line" | tr -cd '|' | wc -c)
    if [[ $pipe_count -ge 5 ]]; then
        return 0
    fi
    
    # Check if it's a beautified ASCII table format (starts with +---)
    if [[ "$first_line" =~ ^\+.*\+$ ]]; then
        return 0
    fi
    
    return 1
}

# Helper function to convert beautified table to raw format
convert_table_to_raw() {
    local input_file="$1"
    local output_file="$2"

    # Write header
    echo "Name|IP|Username|Password|Port|Group|AdditionalInfo" > "$output_file"
    
    # Process the file: extract only data rows, skip headers and separators
    grep "^|" "$input_file" | \
        grep -v -i "name.*ip.*username" | \
        grep -v "^\+\-" | \
        while IFS= read -r line; do
            # Remove leading and trailing |
            line=$(echo "$line" | sed 's/^[[:space:]]*|//' | sed 's/|[[:space:]]*$//')
            # Replace multiple spaces/tabs around | with single |
            line=$(echo "$line" | sed 's/[[:space:]]*|[[:space:]]*/|/g')
            # Trim leading/trailing spaces
            line=$(echo "$line" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')
            # Only output if it's not empty and doesn't contain "Name" as first field
            if [[ -n "$line" ]] && [[ ! "$line" =~ ^[Nn]ame\| ]]; then
                echo "$line"
            fi
        done >> "$output_file"
}

# Vault management menu
show_vault_menu() {
    local show_menu_header=true
    while true; do
        if [[ "$show_menu_header" == "true" ]]; then
            echo -e "\n${BLUE}=== Vault Management ===${NC}"
            if [[ -n "$current_vault_name" ]]; then
                echo -e "${CYAN}Current Vault: ${GREEN}$current_vault_name${NC}"
            else
                echo -e "${YELLOW}No vault selected${NC}"
            fi
            echo
            echo "1. Create New Vault"
            echo "2. List All Vaults"
            echo "3. Select Vault"
            echo "4. Import Vault"
            echo "5. Export Vault"
            echo "6. Rename Vault"
            echo "7. Delete Vault"
            echo "8. Vault Information"
            echo "0. Back to Main Menu"
            echo -e "${RED}q. Quit${NC}"
        fi
        show_menu_header=true
        read -p "$(get_beautiful_prompt)" choice
        case $choice in
            1) create_vault; continue_or_exit_vault_menu ;;
            2) list_vaults || true; continue_or_exit_vault_menu ;;
            3) select_vault; continue_or_exit_vault_menu ;;
            4) import_vault; continue_or_exit_vault_menu ;;
            5) export_vault; continue_or_exit_vault_menu ;;
            6) rename_vault; continue_or_exit_vault_menu ;;
            7) delete_vault ;;
            8) show_vault_info; continue_or_exit_vault_menu ;;
            0) return 0 ;;
            [qQ]) cleanup ;;
            *) echo -e "${RED}Invalid choice. Please try again.${NC}"; show_menu_header=false ;;
        esac
    done
}

 