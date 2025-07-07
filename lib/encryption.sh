#!/bin/bash

# ============================================================================
# ENCRYPTION MODULE
# ============================================================================

# Master passphrase management
setup_master_passphrase() {
    echo -e "${BLUE}No master passphrase set. Please create one now.${NC}"
    while true; do
        read -s -p "Set master passphrase: " pass1; echo
        read -s -p "Confirm master passphrase: " pass2; echo
        if [[ "$pass1" != "$pass2" ]]; then
            echo -e "${RED}Passphrases do not match. Try again.${NC}"
        elif [[ -z "$pass1" ]]; then
            echo -e "${RED}Passphrase cannot be empty.${NC}"
        else
            echo -n "$pass1" | sha256sum | awk '{print $1}' > "$master_hash_file"
            chmod 600 "$master_hash_file"
            master_passphrase="$pass1"
            break
        fi
    done
}

verify_master_passphrase() {
    local stored_hash=""
    if [[ -f "$master_hash_file" ]]; then
        stored_hash=$(cat "$master_hash_file")
    else
        setup_master_passphrase
        return
    fi
    
    # Check rate limit before allowing login attempts
    if ! check_rate_limit "login"; then
        return 1
    fi
    
    for attempt in {1..3}; do
        read -s -p "Enter master passphrase: " input_pass; echo
        local input_hash=$(echo -n "$input_pass" | sha256sum | awk '{print $1}')
        
        if [[ "$input_hash" == "$stored_hash" ]]; then
            master_passphrase="$input_pass"
            # Reset rate limit on successful login
            RATE_LIMITS[login_attempts]=0
            log_security_event "LOGIN_SUCCESS" "Master passphrase verified successfully" "INFO"
            return
        else
            update_rate_limit "login"
            echo -e "${RED}Incorrect master passphrase. Try again.${NC}"
            log_security_event "LOGIN_FAILED" "Failed master passphrase attempt $attempt/3" "WARNING"
        fi
    done
    
    echo -e "${RED}Too many failed attempts. Exiting.${NC}"
    log_security_event "LOGIN_LOCKOUT" "Master passphrase lockout after 3 failed attempts" "CRITICAL"
    exit 1
}

# Encryption functions
encrypt_vault() {
    local input_file="$1"
    local output_file="$2"
    
    if [[ ! -f "$input_file" ]]; then
        echo -e "${RED}Input file not found: $input_file${NC}"
        return 1
    fi
    
    # Add SVM header for identification
    echo "SVM:${CONFIG[VAULT_VERSION]}:${CONFIG[CIPHER]}:${CONFIG[DIGEST]}:$(date +%s)" > "$output_file"
    
    # Encrypt the content
    if openssl enc -${CONFIG[CIPHER]} -pbkdf2 -iter ${CONFIG[PBKDF2_ITERATIONS]} -md ${CONFIG[DIGEST]} -salt -in "$input_file" -out "$output_file.tmp" -pass pass:"$passphrase" 2>/dev/null; then
        # Append encrypted content to header
        cat "$output_file.tmp" >> "$output_file"
        rm -f "$output_file.tmp"
        
        # Set secure permissions
        chmod 600 "$output_file"
        
        # Verify file integrity
        if ! verify_file_ownership "$output_file" || ! verify_file_permissions "$output_file"; then
            echo -e "${RED}Failed to set secure permissions on encrypted file.${NC}"
            rm -f "$output_file"
            return 1
        fi
        
        log_security_event "VAULT_ENCRYPTED" "Vault encrypted successfully: $output_file" "INFO"
        return 0
    else
        echo -e "${RED}Encryption failed.${NC}"
        rm -f "$output_file" "$output_file.tmp" 2>/dev/null
        log_security_event "ENCRYPTION_FAILED" "Failed to encrypt vault: $input_file" "ERROR"
        return 1
    fi
}

decrypt_vault() {
    local input_file="$1"
    local output_file="$2"
    
    if [[ ! -f "$input_file" ]]; then
        echo -e "${RED}Input file not found: $input_file${NC}"
        return 1
    fi
    
    # Check if file has SVM header
    local first_line
    first_line=$(head -n 1 "$input_file")
    
    if [[ "$first_line" =~ ^SVM: ]]; then
        # Extract encrypted content (skip header)
        tail -n +2 "$input_file" > "$output_file.tmp"
        
        # Decrypt the content
        if openssl enc -${CONFIG[CIPHER]} -pbkdf2 -iter ${CONFIG[PBKDF2_ITERATIONS]} -md ${CONFIG[DIGEST]} -d -in "$output_file.tmp" -out "$output_file" -pass pass:"$passphrase" 2>/dev/null; then
            rm -f "$output_file.tmp"
            log_security_event "VAULT_DECRYPTED" "Vault decrypted successfully: $input_file" "INFO"
            return 0
        else
            echo -e "${RED}Decryption failed. Check your passphrase.${NC}"
            rm -f "$output_file" "$output_file.tmp" 2>/dev/null
            log_security_event "DECRYPTION_FAILED" "Failed to decrypt vault: $input_file" "ERROR"
            return 1
        fi
    else
        # Legacy format or non-SVM file
        if openssl enc -${CONFIG[CIPHER]} -pbkdf2 -iter ${CONFIG[PBKDF2_ITERATIONS]} -md ${CONFIG[DIGEST]} -d -in "$input_file" -out "$output_file" -pass pass:"$passphrase" 2>/dev/null; then
            log_security_event "VAULT_DECRYPTED" "Legacy vault decrypted successfully: $input_file" "INFO"
            return 0
        else
            echo -e "${RED}Decryption failed. Check your passphrase.${NC}"
            rm -f "$output_file" 2>/dev/null
            log_security_event "DECRYPTION_FAILED" "Failed to decrypt legacy vault: $input_file" "ERROR"
            return 1
        fi
    fi
}

# Prompt for vault passphrase (now uses master passphrase)
prompt_passphrase() {
    if [[ -z "$current_vault_name" ]]; then
        echo -e "${RED}No vault selected. Please select a vault first.${NC}"
        return 1
    fi
    
    # Use master passphrase for all vault operations
    if [[ -z "$master_passphrase" ]]; then
        echo -e "${RED}Master passphrase not available. Please restart the application.${NC}"
        return 1
    fi
    
    # Set passphrase to master passphrase
    passphrase="$master_passphrase"
    PASSPHRASE_TIMESTAMP=$(date +%s)
    
    log_security_event "PASSPHRASE_SET" "Using master passphrase for vault: $current_vault_name" "INFO"
    return 0
}

# Check if vault file exists and is accessible
check_file() {
    if [[ ! -f "$servers_file" ]]; then
        echo -e "${YELLOW}No vault file found. Creating new vault...${NC}"
        
        # Use master passphrase for new vault
        if [[ -z "$master_passphrase" ]]; then
            echo -e "${RED}Master passphrase not available. Cannot create vault.${NC}"
            return 1
        fi
        
        passphrase="$master_passphrase"
        PASSPHRASE_TIMESTAMP=$(date +%s)
        
        # Create empty temporary file
        touch "$tmp_servers_file"
        chmod 600 "$tmp_servers_file"
        
        # Encrypt and save the empty vault
        if encrypt_vault "$tmp_servers_file" "$servers_file"; then
            log_event "VAULT_CREATED" "New vault file created: $servers_file"
        else
            echo -e "${RED}Failed to create vault file.${NC}"
            return 1
        fi
    else
        # Vault file exists, decrypt it to populate tmp_servers_file
        if [[ -z "$master_passphrase" ]]; then
            echo -e "${RED}Master passphrase not available. Cannot decrypt vault.${NC}"
            return 1
        fi
        
        passphrase="$master_passphrase"
        PASSPHRASE_TIMESTAMP=$(date +%s)
        
        # Decrypt the existing vault
        if ! decrypt_vault "$servers_file" "$tmp_servers_file"; then
            echo -e "${RED}Failed to decrypt vault. Check your master passphrase.${NC}"
            return 1
        fi
        
        # Set secure permissions on decrypted file
        chmod 600 "$tmp_servers_file"
        log_event "VAULT_LOADED" "Existing vault decrypted and loaded: $servers_file"
    fi
    
    # Verify file integrity
    if ! verify_file_ownership "$servers_file" || ! verify_file_permissions "$servers_file"; then
        echo -e "${RED}Vault file integrity check failed.${NC}"
        log_security_event "VAULT_INTEGRITY_FAILED" "Vault file integrity check failed: $servers_file" "CRITICAL"
        return 1
    fi
    
    return 0
}

# Save vault with encryption
save_vault() {
    if [[ -f "$tmp_servers_file" ]]; then
        if encrypt_vault "$tmp_servers_file" "$servers_file"; then
            echo -e "${GREEN}Vault saved successfully.${NC}"
            log_event "VAULT_SAVED" "Vault saved: $servers_file"
            return 0
        else
            echo -e "${RED}Failed to save vault.${NC}"
            return 1
        fi
    else
        echo -e "${RED}No temporary file to save.${NC}"
        return 1
    fi
} 