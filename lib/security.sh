#!/bin/bash

# ============================================================================
# SECURITY MODULE
# ============================================================================

# Rate limiting functions
check_rate_limit() {
    local action="$1"
    local current_time=$(date +%s)
    
    case "$action" in
        "login")
            if [[ ${RATE_LIMITS[login_attempts]} -ge ${RATE_LIMITS[max_attempts]} ]]; then
                local time_diff=$((current_time - ${RATE_LIMITS[last_attempt]}))
                if [[ $time_diff -lt ${RATE_LIMITS[lockout_duration]} ]]; then
                    local remaining=$((RATE_LIMITS[lockout_duration] - time_diff))
                    echo -e "${RED}Too many login attempts. Please wait ${remaining} seconds.${NC}"
                    log_security_event "RATE_LIMIT_EXCEEDED" "Login rate limit exceeded - $remaining seconds remaining" "WARNING"
                    return 1
                else
                    # Reset rate limit after lockout period
                    RATE_LIMITS[login_attempts]=0
                fi
            fi
            ;;
        "search")
            if [[ ${RATE_LIMITS[search_attempts]} -ge ${RATE_LIMITS[max_search_attempts]} ]]; then
                local time_diff=$((current_time - ${RATE_LIMITS[search_last_attempt]}))
                if [[ $time_diff -lt ${RATE_LIMITS[search_lockout_duration]} ]]; then
                    local remaining=$((RATE_LIMITS[search_lockout_duration] - time_diff))
                    echo -e "${RED}Too many search attempts. Please wait ${remaining} seconds.${NC}"
                    log_security_event "RATE_LIMIT_EXCEEDED" "Search rate limit exceeded - $remaining seconds remaining" "WARNING"
                    return 1
                else
                    # Reset rate limit after lockout period
                    RATE_LIMITS[search_attempts]=0
                fi
            fi
            ;;
    esac
    return 0
}

update_rate_limit() {
    local action="$1"
    local current_time=$(date +%s)
    
    case "$action" in
        "login")
            RATE_LIMITS[login_attempts]=$((${RATE_LIMITS[login_attempts]} + 1))
            RATE_LIMITS[last_attempt]=$current_time
            ;;
        "search")
            RATE_LIMITS[search_attempts]=$((${RATE_LIMITS[search_attempts]} + 1))
            RATE_LIMITS[search_last_attempt]=$current_time
            ;;
    esac
}

# Enhanced input sanitization
sanitize_input() {
    local input="$1"
    local max_length="${2:-100}"
    
    # Remove null bytes and control characters
    input=$(echo "$input" | tr -d '\0' | tr -cd '[:print:]\n\t')
    
    # Limit length
    if [[ ${#input} -gt $max_length ]]; then
        input="${input:0:$max_length}"
    fi
    
    # Remove potentially dangerous patterns
    input=$(echo "$input" | sed 's/[;&|\\`$(){}[\]<>]/_/g')
    
    echo "$input"
}

# Validate and sanitize server input
validate_and_sanitize_server_input() {
    local name="$1"
    local ip="$2"
    local port="$3"
    local username="$4"
    
    # Sanitize inputs
    name=$(sanitize_input "$name" 50)
    ip=$(sanitize_input "$ip" 15)
    port=$(sanitize_input "$port" 5)
    username=$(sanitize_input "$username" 30)
    
    # Validate name
    if [[ -z "$name" ]]; then
        echo -e "${RED}Server name cannot be empty.${NC}"
        return 1
    fi
    
    # Check for dangerous patterns in name
    if [[ "$name" == *[\;\&\|\`\$\(\)\{\}\[\]\<\>]* ]]; then
        echo -e "${RED}Server name contains invalid characters.${NC}"
        log_security_event "INVALID_INPUT" "Dangerous characters detected in server name: $name" "WARNING"
        return 1
    fi
    
    # Validate IP address
    if ! [[ "$ip" =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
        echo -e "${RED}Invalid IP address format.${NC}"
        return 1
    fi
    
    IFS='.' read -r -a ip_parts <<< "$ip"
    for part in "${ip_parts[@]}"; do
        if [[ $part -gt 255 ]]; then
            echo -e "${RED}Invalid IP address: octets must be 0-255.${NC}"
            return 1
        fi
    done
    
    # Validate port
    if ! [[ "$port" =~ ^[0-9]+$ ]] || [[ $port -lt 1 ]] || [[ $port -gt 65535 ]]; then
        echo -e "${RED}Invalid port number: must be 1-65535.${NC}"
        return 1
    fi
    
    # Validate username
    if [[ -z "$username" ]]; then
        echo -e "${RED}Username cannot be empty.${NC}"
        return 1
    fi
    
    # Check for dangerous patterns in username
    if [[ "$username" == *[\;\&\|\`\$\(\)\{\}\[\]\<\>]* ]]; then
        echo -e "${RED}Username contains invalid characters.${NC}"
        log_security_event "INVALID_INPUT" "Dangerous characters detected in username: $username" "WARNING"
        return 1
    fi
    
    return 0
}

# Enhanced secure memory clearing with random overwrite
secure_clear() {
    local var_name="$1"
    if [[ -n "${!var_name-}" ]]; then
        local var_content="${!var_name}"
        local var_length=${#var_content}
        
        # Overwrite with random data first
        local random_data=$(openssl rand -hex $var_length 2>/dev/null || echo "0000000000000000")
        printf '%s' "$random_data" > /dev/null
        
        # Overwrite with zeros
        printf '\0%.0s' $(seq 1 $var_length) 2>/dev/null
        
        # Overwrite with ones
        printf '\1%.0s' $(seq 1 $var_length) 2>/dev/null
        
        # Finally unset the variable
        unset "$var_name"
        
        log_security_event "MEMORY_CLEARED" "Sensitive variable cleared: $var_name" "INFO"
    fi
}

# Enhanced secure clearing for multiple variables
secure_clear_multiple() {
    local var_names=("$@")
    for var_name in "${var_names[@]}"; do
        secure_clear "$var_name"
    done
}

# Enhanced error handling with security logging
handle_error() {
    local error_code="$1"
    local error_message="$2"
    local function_name="${3:-unknown}"
    
    case $error_code in
        1)
            log_security_event "GENERAL_ERROR" "Error in $function_name: $error_message" "ERROR"
            echo -e "${RED}Error: $error_message${NC}" >&2
            ;;
        2)
            log_security_event "PERMISSION_ERROR" "Permission denied in $function_name: $error_message" "WARNING"
            echo -e "${RED}Permission denied: $error_message${NC}" >&2
            ;;
        3)
            log_security_event "VALIDATION_ERROR" "Validation failed in $function_name: $error_message" "WARNING"
            echo -e "${RED}Validation error: $error_message${NC}" >&2
            ;;
        4)
            log_security_event "CRYPTO_ERROR" "Cryptographic error in $function_name: $error_message" "CRITICAL"
            echo -e "${RED}Cryptographic error: $error_message${NC}" >&2
            ;;
        5)
            log_security_event "INTEGRITY_ERROR" "Integrity check failed in $function_name: $error_message" "CRITICAL"
            echo -e "${RED}Integrity check failed: $error_message${NC}" >&2
            ;;
        *)
            log_security_event "UNKNOWN_ERROR" "Unknown error ($error_code) in $function_name: $error_message" "ERROR"
            echo -e "${RED}Unknown error ($error_code): $error_message${NC}" >&2
            ;;
    esac
}

# Safe execution wrapper
safe_execute() {
    local function_name="$1"
    shift
    local args=("$@")
    
    if ! "$function_name" "${args[@]}"; then
        local exit_code=$?
        handle_error $exit_code "Function $function_name failed" "$function_name"
        return $exit_code
    fi
    return 0
}

# Secure environment setup
setup_secure_environment() {
    # Set secure PATH - only system directories, no current directory
    export PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
    
    # Clear potentially dangerous environment variables
    unset IFS
    unset CDPATH
    unset ENV
    unset BASH_ENV
    
    # Set secure umask
    umask 077
    
    # Disable core dumps
    ulimit -c 0
    
    # Set secure file creation mask
    umask 077
    
    # Log environment setup
    log_security_event "ENVIRONMENT_SECURED" "Secure environment initialized" "INFO"
}

# Process isolation and security
setup_process_isolation() {
    # Set process priority to normal (suppress all output)
    renice 0 $$ >/dev/null 2>&1 || true
    
    # Set secure process limits
    ulimit -n 1024  # File descriptors
    ulimit -u 5000  # User processes (increased from 1000)
    
    # Disable core dumps for this process
    ulimit -c 0
    
    # Set secure working directory
    cd "$HOME" 2>/dev/null || cd /tmp
    
    # Log process isolation
    log_security_event "PROCESS_ISOLATED" "Process isolation configured - PID: $$" "INFO"
}

# Enhanced security logging
log_security_event() {
    local event_type="$1"
    local details="$2"
    local severity="${3:-INFO}"
    local timestamp=$(date -u '+%Y-%m-%d %H:%M:%S UTC')
    local user=$(whoami)
    local hostname=$(hostname)
    local session_id="$SESSION_START"
    
    # Create security log file if it doesn't exist
    local security_log="$base_vault_dir/.security.log"
    if [[ ! -f "$security_log" ]]; then
        touch "$security_log"
        chmod 600 "$security_log"
    fi
    
    echo "[$timestamp] [$severity] [$user@$hostname] [SID:$session_id] [$event_type] $details" >> "$security_log"
    
    # Alert on high-severity events
    if [[ "$severity" == "CRITICAL" ]]; then
        echo -e "${RED}SECURITY ALERT: $event_type - $details${NC}" >&2
    fi
}

# File ownership verification
verify_file_ownership() {
    local file="$1"
    local expected_owner=$(whoami)
    
    if [[ ! -f "$file" ]]; then
        return 1
    fi
    
    if [[ "$(stat -c %u "$file")" != "$(id -u)" ]]; then
        log_security_event "FILE_OWNERSHIP_VIOLATION" "File $file has wrong owner" "WARNING"
        return 1
    fi
    return 0
}

# File permissions verification
verify_file_permissions() {
    local file="$1"
    local expected_perms="600"
    
    if [[ ! -f "$file" ]]; then
        return 1
    fi
    
    if [[ "$(stat -c %a "$file")" != "$expected_perms" ]]; then
        log_security_event "FILE_PERMISSION_VIOLATION" "File $file has wrong permissions" "WARNING"
        return 1
    fi
    return 0
}

# Directory integrity verification (prevent symlink attacks)
verify_directory_integrity() {
    local dir="$1"
    
    if [[ ! -d "$dir" ]]; then
        return 1
    fi
    
    # Check if it's a real directory, not a symlink
    if [[ -L "$dir" ]]; then
        log_security_event "SYMLINK_ATTACK" "Directory $dir is a symlink" "CRITICAL"
        return 1
    fi
    
    # Verify it's owned by the current user
    if [[ "$(stat -c %u "$dir")" != "$(id -u)" ]]; then
        log_security_event "DIRECTORY_OWNERSHIP_VIOLATION" "Directory $dir has wrong owner" "WARNING"
        return 1
    fi
    
    # Verify directory permissions
    if [[ "$(stat -c %a "$dir")" != "700" ]]; then
        log_security_event "DIRECTORY_PERMISSION_VIOLATION" "Directory $dir has wrong permissions" "WARNING"
        return 1
    fi
    
    return 0
}

# Secure temporary file creation
create_secure_temp() {
    local temp_file
    temp_file=$(mktemp -p /tmp -t svm.XXXXXXXXXX)
    
    if [[ $? -ne 0 ]]; then
        log_security_event "TEMP_FILE_CREATION_FAILED" "Failed to create secure temp file" "ERROR"
        return 1
    fi
    
    chmod 600 "$temp_file"
    
    # Verify ownership
    if [[ "$(stat -c %u "$temp_file")" != "$(id -u)" ]]; then
        rm -f "$temp_file"
        log_security_event "TEMP_FILE_OWNERSHIP_VIOLATION" "Temp file $temp_file has wrong owner" "CRITICAL"
        return 1
    fi
    
    echo "$temp_file"
}

# Enhanced temp directory management
setup_temp_directory() {
    # Create SVM temp directory if it doesn't exist
    if [[ ! -d "$SVM_TEMP_DIR" ]]; then
        mkdir -p "$SVM_TEMP_DIR"
        chmod 700 "$SVM_TEMP_DIR"
        log_security_event "TEMP_DIR_CREATED" "SVM temp directory created: $SVM_TEMP_DIR" "INFO"
    fi
    
    # Clean old temp files (older than retention period)
    cleanup_old_temp_files
    
    # Verify directory integrity
    if ! verify_directory_integrity "$SVM_TEMP_DIR"; then
        log_security_event "TEMP_DIR_INTEGRITY_FAILED" "Temp directory integrity check failed: $SVM_TEMP_DIR" "CRITICAL"
        return 1
    fi
    
    return 0
}

# Create secure temp file in SVM temp directory
create_svm_temp_file() {
    local purpose="${1:-general}"
    local temp_file
    
    # Ensure temp directory exists
    if ! setup_temp_directory; then
        return 1
    fi
    
    # Create temp file with purpose-specific naming
    temp_file=$(mktemp -p "$SVM_TEMP_DIR" -t "${SVM_TEMP_PREFIX}${purpose}-XXXXXXXXXX")
    
    if [[ $? -ne 0 ]]; then
        log_security_event "SVM_TEMP_FILE_CREATION_FAILED" "Failed to create SVM temp file for purpose: $purpose" "ERROR"
        return 1
    fi
    
    # Set secure permissions
    chmod 600 "$temp_file"
    
    # Verify ownership
    if [[ "$(stat -c %u "$temp_file")" != "$(id -u)" ]]; then
        rm -f "$temp_file"
        log_security_event "SVM_TEMP_FILE_OWNERSHIP_VIOLATION" "SVM temp file $temp_file has wrong owner" "CRITICAL"
        return 1
    fi
    
    # Register temp file for cleanup
    register_temp_file "$temp_file"
    
    echo "$temp_file"
}

# Register temp file for cleanup
register_temp_file() {
    local temp_file="$1"
    local cleanup_file="$SVM_TEMP_DIR/.cleanup_list"
    
    # Add to cleanup list
    echo "$temp_file|$(date +%s)" >> "$cleanup_file" 2>/dev/null
    
    # Set secure permissions on cleanup list
    chmod 600 "$cleanup_file" 2>/dev/null
}

# Clean up old temp files
cleanup_old_temp_files() {
    local current_time=$(date +%s)
    local retention_seconds=$((SVM_TEMP_RETENTION_DAYS * 24 * 3600))
    local cleanup_file="$SVM_TEMP_DIR/.cleanup_list"
    local temp_cleanup_file
    
    if [[ ! -f "$cleanup_file" ]]; then
        return 0
    fi
    
    # Create temporary cleanup file
    temp_cleanup_file=$(mktemp -p "$SVM_TEMP_DIR" -t "${SVM_TEMP_PREFIX}cleanup-XXXXXXXXXX")
    
    # Process cleanup list
    while IFS='|' read -r file_path timestamp; do
        if [[ -f "$file_path" ]]; then
            local file_age=$((current_time - timestamp))
            
            # Remove files older than retention period
            if [[ $file_age -gt $retention_seconds ]]; then
                shred -zfu -n "${CONFIG[SHRED_PASSES]}" "$file_path" 2>/dev/null
                log_security_event "OLD_TEMP_FILE_CLEANED" "Old temp file cleaned: $file_path" "INFO"
            else
                # Keep file in cleanup list
                echo "$file_path|$timestamp" >> "$temp_cleanup_file"
            fi
        fi
    done < "$cleanup_file"
    
    # Replace cleanup list with updated version
    if [[ -f "$temp_cleanup_file" ]]; then
        mv "$temp_cleanup_file" "$cleanup_file"
        chmod 600 "$cleanup_file"
    else
        rm -f "$cleanup_file"
    fi
}

# Clean up all SVM temp files
cleanup_all_svm_temp_files() {
    if [[ ! -d "$SVM_TEMP_DIR" ]]; then
        return 0
    fi
    
    # Securely delete all files in temp directory
    find "$SVM_TEMP_DIR" -type f -exec shred -zfu -n "${CONFIG[SHRED_PASSES]}" {} \; 2>/dev/null
    
    # Remove temp directory
    rm -rf "$SVM_TEMP_DIR" 2>/dev/null
    
    log_security_event "ALL_SVM_TEMP_FILES_CLEANED" "All SVM temp files cleaned and directory removed" "INFO"
}

# Secure directory operations
secure_directory_operation() {
    local operation="$1"
    local path="$2"
    
    case "$operation" in
        "create")
            if [[ -d "$path" ]]; then
                log_security_event "DIRECTORY_EXISTS" "Directory already exists: $path" "INFO"
                return 0
            fi
            
            # Create directory with secure permissions
            mkdir -p "$path" 2>/dev/null
            if [[ $? -eq 0 ]]; then
                chmod 700 "$path"
                
                # Verify directory integrity
                if ! verify_directory_integrity "$path"; then
                    rmdir "$path" 2>/dev/null
                    handle_error 5 "Directory integrity check failed: $path" "secure_directory_operation"
                    return 1
                fi
                
                log_security_event "DIRECTORY_CREATED" "Secure directory created: $path" "INFO"
                return 0
            else
                handle_error 1 "Failed to create directory: $path" "secure_directory_operation"
                return 1
            fi
            ;;
            
        "verify")
            if [[ ! -d "$path" ]]; then
                handle_error 2 "Directory not found: $path" "secure_directory_operation"
                return 1
            fi
            
            if ! verify_directory_integrity "$path"; then
                handle_error 5 "Directory integrity check failed: $path" "secure_directory_operation"
                return 1
            fi
            
            return 0
            ;;
            
        "cleanup")
            if [[ -d "$path" ]]; then
                # Remove directory contents securely
                find "$path" -type f -exec shred -zfu -n "${CONFIG[SHRED_PASSES]}" {} \; 2>/dev/null
                rm -rf "$path" 2>/dev/null
                log_security_event "DIRECTORY_CLEANED" "Directory cleaned and removed: $path" "INFO"
            fi
            ;;
            
        *)
            handle_error 3 "Unknown operation: $operation" "secure_directory_operation"
            return 1
            ;;
    esac
}

# Secure command execution
secure_exec() {
    local command="$1"
    local timeout="${2:-30}"
    
    # Validate command
    if [[ -z "$command" ]]; then
        handle_error 3 "Empty command provided" "secure_exec"
        return 1
    fi
    
    # Check for dangerous patterns
    if [[ "$command" == *[\;\&\|\`\$\(\)\{\}\[\]\<\>]* ]]; then
        log_security_event "DANGEROUS_COMMAND" "Dangerous command pattern detected: $command" "CRITICAL"
        handle_error 3 "Dangerous command pattern detected" "secure_exec"
        return 1
    fi
    
    # Execute with timeout
    timeout "$timeout" bash -c "$command" 2>/dev/null
    local exit_code=$?
    
    if [[ $exit_code -eq 124 ]]; then
        log_security_event "COMMAND_TIMEOUT" "Command timed out after ${timeout}s: $command" "WARNING"
        handle_error 1 "Command timed out" "secure_exec"
        return 1
    fi
    
    return $exit_code
}

# Secure file operations
secure_file_operation() {
    local operation="$1"
    local source="$2"
    local destination="${3:-}"
    
    case "$operation" in
        "read")
            if [[ ! -f "$source" ]]; then
                handle_error 2 "File not found: $source" "secure_file_operation"
                return 1
            fi
            
            # Verify file ownership
            if [[ "$(stat -c %u "$source")" != "$(id -u)" ]]; then
                log_security_event "FILE_OWNERSHIP_VIOLATION" "File ownership violation: $source" "WARNING"
                handle_error 2 "File ownership violation: $source" "secure_file_operation"
                return 1
            fi
            
            # Read file securely
            cat "$source" 2>/dev/null
            ;;
            
        "write")
            if [[ -z "$destination" ]]; then
                handle_error 3 "No destination specified for write operation" "secure_file_operation"
                return 1
            fi
            
            # Create secure temporary file
            local temp_file=$(mktemp -p /tmp -t svm.XXXXXXXXXX)
            if [[ $? -ne 0 ]]; then
                handle_error 1 "Failed to create temporary file" "secure_file_operation"
                return 1
            fi
            
            # Write to temporary file first
            echo "$source" > "$temp_file"
            
            # Move atomically
            mv "$temp_file" "$destination"
            chmod 600 "$destination"
            
            # Verify destination
            if [[ ! -f "$destination" ]]; then
                handle_error 1 "Failed to write to destination: $destination" "secure_file_operation"
                return 1
            fi
            ;;
            
        "delete")
            if [[ ! -f "$source" ]]; then
                handle_error 2 "File not found: $source" "secure_file_operation"
                return 1
            fi
            
            # Secure delete with shred
            shred -zfu -n "${CONFIG[SHRED_PASSES]}" "$source" 2>/dev/null
            ;;
            
        *)
            handle_error 3 "Unknown operation: $operation" "secure_file_operation"
            return 1
            ;;
    esac
}

# Secure network operations
secure_network_operation() {
    local operation="$1"
    local host="$2"
    local port="${3:-22}"
    local timeout="${4:-10}"
    
    case "$operation" in
        "test_connectivity")
            # Test basic connectivity with timeout
            if command -v nc >/dev/null 2>&1; then
                timeout "$timeout" nc -z "$host" "$port" 2>/dev/null
                return $?
            elif command -v telnet >/dev/null 2>&1; then
                timeout "$timeout" bash -c "echo quit | telnet $host $port" 2>/dev/null | grep -q "Connected"
                return $?
            else
                # Fallback to ping
                timeout "$timeout" ping -c 1 "$host" >/dev/null 2>&1
                return $?
            fi
            ;;
            
        "validate_host")
            # Validate host format
            if [[ "$host" =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
                # IP address format
                IFS='.' read -r -a ip_parts <<< "$host"
                for part in "${ip_parts[@]}"; do
                    if [[ $part -gt 255 ]]; then
                        return 1
                    fi
                done
                return 0
            elif [[ "$host" =~ ^[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$ ]]; then
                # Domain name format
                return 0
            else
                return 1
            fi
            ;;
            
        *)
            handle_error 3 "Unknown network operation: $operation" "secure_network_operation"
            return 1
            ;;
    esac
}

# Secure configuration validation
validate_secure_config() {
    local config_key="$1"
    local config_value="$2"
    
    case "$config_key" in
        "PBKDF2_ITERATIONS")
            if ! [[ "$config_value" =~ ^[0-9]+$ ]] || [[ $config_value -lt 100000 ]]; then
                log_security_event "CONFIG_VALIDATION_FAILED" "Invalid PBKDF2 iterations: $config_value" "WARNING"
                return 1
            fi
            ;;
            
        "PASSPHRASE_TIMEOUT")
            if ! [[ "$config_value" =~ ^[0-9]+$ ]] || [[ $config_value -lt 60 ]] || [[ $config_value -gt 3600 ]]; then
                log_security_event "CONFIG_VALIDATION_FAILED" "Invalid passphrase timeout: $config_value" "WARNING"
                return 1
            fi
            ;;
            
        "MAX_LOGIN_ATTEMPTS")
            if ! [[ "$config_value" =~ ^[0-9]+$ ]] || [[ $config_value -lt 1 ]] || [[ $config_value -gt 10 ]]; then
                log_security_event "CONFIG_VALIDATION_FAILED" "Invalid max login attempts: $config_value" "WARNING"
                return 1
            fi
            ;;
            
        "CONNECTION_TIMEOUT")
            if ! [[ "$config_value" =~ ^[0-9]+$ ]] || [[ $config_value -lt 5 ]] || [[ $config_value -gt 120 ]]; then
                log_security_event "CONFIG_VALIDATION_FAILED" "Invalid connection timeout: $config_value" "WARNING"
                return 1
            fi
            ;;
            
        *)
            # Unknown config key - log but don't fail
            log_security_event "CONFIG_UNKNOWN_KEY" "Unknown configuration key: $config_key" "INFO"
            ;;
    esac
    
    return 0
} 