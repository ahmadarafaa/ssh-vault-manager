#!/bin/bash

# ============================================================================
# UTILITIES MODULE
# ============================================================================

# Initialize file paths
init_file_paths() {
    servers_file="$vault/${CONFIG[VAULT_NAME]}"
    config_file="$vault/${CONFIG[CONFIG_NAME]}"
    log_file="$vault/${CONFIG[LOG_NAME]}"
    tmp_servers_file="$(create_svm_temp_file 'vault')"
    if [[ $? -ne 0 ]]; then
        echo -e "${RED}Failed to create secure temporary file.${NC}"
        return 1
    fi
}

# Enhanced logging function
log_event() {
    local event_type="$1"
    local message="$2"
    local server_info="${3:-}"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    local session_id="${SESSION_START}"
    # Prevent logging if log_file is empty or its directory does not exist
    if [[ -z "$log_file" || ! -d "$(dirname "$log_file")" ]]; then
        return
    fi
    local log_entry="[$timestamp] [SID:$session_id] [$event_type] $message"
    [[ -n "$server_info" ]] && log_entry="$log_entry [$server_info]"
    echo "$log_entry" >> "$log_file"
    # Rotate log if too large
    if [[ -f "$log_file" ]]; then
        local line_count=$(wc -l < "$log_file")
        if [[ $line_count -gt ${CONFIG[LOG_MAX_LINES]} ]]; then
            tail -n $((${CONFIG[LOG_MAX_LINES]} / 2)) "$log_file" > "${log_file}.tmp"
            mv "${log_file}.tmp" "$log_file"
        fi
    fi
}

# Save statistics
save_statistics() {
    local stats_file="$vault/.stats"
    # Prevent saving if the vault directory does not exist or vault is empty or '/'
    if [[ -z "$vault" || "$vault" == "/" || ! -d "$vault" ]]; then
        return
    fi
    {
        echo "# SVM Statistics - $(date)"
        echo "session_start=$SESSION_START"
        echo "session_duration=$(($(date +%s) - SESSION_START))"
        for stat in "${!STATS[@]}"; do
            echo "${stat}=${STATS[$stat]}"
        done
    } >> "$stats_file"
}

# Display statistics
show_statistics() {
    local stats_file="$vault/.stats"
    echo -e "\n${BLUE}=== Connection Statistics ===${NC}"
    echo -e "${CYAN}Current Session:${NC}"
    echo -e "  Duration: $(($(date +%s) - SESSION_START)) seconds"
    echo -e "  Connections Attempted: ${STATS[connections_attempted]}"
    echo -e "  Successful: ${STATS[connections_successful]}"
    echo -e "  Failed: ${STATS[connections_failed]}"
    echo -e "  Vault Operations: ${STATS[vault_operations]}"
    
    if [[ ${STATS[connections_attempted]} -gt 0 ]]; then
        local success_rate=$((${STATS[connections_successful]} * 100 / ${STATS[connections_attempted]}))
        echo -e "  Success Rate: ${success_rate}%"
    fi
    
    if [[ -f "$stats_file" ]]; then
        echo -e "\n${CYAN}Historical Data:${NC}"
        echo -e "  Previous sessions logged: $(grep -c "session_start" "$stats_file" 2>/dev/null || echo 0)"
    fi
}

# Enhanced cleanup function
cleanup() {
    if [[ "$CLEANED_UP" == "true" ]]; then
        exit 0
    fi
    CLEANED_UP=true
    echo -e "\n${YELLOW}Cleaning up...${NC}"
    
    # Log security event for session termination
    log_security_event "SESSION_TERMINATED" "SVM session terminated normally" "INFO"
    
    # Enhanced memory clearing using DOD-standard secure wiping
    for var in "passphrase" "master_passphrase" "password" "input_pass" "export_pass1" "export_pass2" "import_pass"; do
        safe_memory_wipe "$var" 2>/dev/null || true
    done
    
    # Also wipe any additional registered sensitive variables
    if [[ -n "${sensitive_vars[@]}" ]]; then
        sanitize_memory_on_exit "${sensitive_vars[@]}"
    fi
    
    # Clear cache and arrays
    unset VAULT_CACHE
    declare -gA VAULT_CACHE=()
    unset RATE_LIMITS
    declare -gA RATE_LIMITS=()
    
    # Clear command cache
    clear_command_cache
    
    # Secure delete temporary files using SVM temp directory system
    if [[ -f "$tmp_servers_file" ]]; then
        shred -zfu -n "${CONFIG[SHRED_PASSES]}" "$tmp_servers_file" 2>/dev/null
    fi
    
    # Clean up all SVM temp files
    cleanup_all_svm_temp_files
    
    # Save statistics
    save_statistics
    
    # Show performance statistics if operations were performed
    if [[ ${PERFORMANCE_STATS[operations]} -gt 0 ]]; then
        show_performance_stats
    fi
    
    echo -e "${GREEN}Cleanup completed.${NC}"
    exit 0
}

# Verify vault file integrity
verify_vault_integrity() {
    local vault_path="$1"
    local vault_file="$vault_path/${CONFIG[VAULT_NAME]}"
    
    # Verify directory integrity
    if ! verify_directory_integrity "$vault_path"; then
        echo -e "${RED}Directory integrity check failed for: $vault_path${NC}"
        return 1
    fi
    
    # If vault file exists, verify its integrity
    if [[ -f "$vault_file" ]]; then
        if ! verify_file_ownership "$vault_file"; then
            echo -e "${RED}File ownership check failed for: $vault_file${NC}"
            return 1
        fi
        
        if ! verify_file_permissions "$vault_file"; then
            echo -e "${RED}File permission check failed for: $vault_file${NC}"
            return 1
        fi
    fi
    
    return 0
}

# ============================================================================
# PERFORMANCE OPTIMIZATION
# ============================================================================

# Cache command output
cache_command() {
    local command="$1"
    local cache_key=$(echo "$command" | sha256sum | awk '{print $1}')
    local current_time=$(date +%s)
    
    # Check if cache is valid
    if [[ -n "${COMMAND_CACHE[$cache_key]:-}" ]] && \
       [[ $((current_time - ${COMMAND_CACHE_TIMESTAMP[$cache_key]:-0})) -lt $CACHE_TIMEOUT ]]; then
        echo "${COMMAND_CACHE[$cache_key]}"
        return 0
    fi
    
    # Execute command and cache result
    local result
    result=$(eval "$command" 2>/dev/null)
    local exit_code=$?
    
    if [[ $exit_code -eq 0 ]]; then
        COMMAND_CACHE["$cache_key"]="$result"
        COMMAND_CACHE_TIMESTAMP["$cache_key"]="$current_time"
        echo "$result"
    else
        return $exit_code
    fi
}

# Clear command cache
clear_command_cache() {
    COMMAND_CACHE=()
    COMMAND_CACHE_TIMESTAMP=()
}

# Optimized file operations using built-ins
fast_file_read() {
    local file="$1"
    local max_lines="${2:-1000}"
    
    if [[ ! -f "$file" ]]; then
        return 1
    fi
    
    # Use built-in read for better performance
    local lines=()
    local line_count=0
    
    while IFS= read -r line && [[ $line_count -lt $max_lines ]]; do
        lines+=("$line")
        ((line_count++))
    done < "$file"
    
    printf '%s\n' "${lines[@]}"
}

# Optimized grep with caching
fast_grep() {
    local pattern="$1"
    local file="$2"
    local cache_key="grep_$(echo "$pattern:$file" | sha256sum | awk '{print $1}')"
    local current_time=$(date +%s)
    
    # Check cache first
    if [[ -n "${COMMAND_CACHE[$cache_key]:-}" ]] && \
       [[ $((current_time - ${COMMAND_CACHE_TIMESTAMP[$cache_key]:-0})) -lt $CACHE_TIMEOUT ]]; then
        echo "${COMMAND_CACHE[$cache_key]}"
        return 0
    fi
    
    # Use optimized grep with early exit
    local result
    result=$(grep -m 1000 "$pattern" "$file" 2>/dev/null)
    local exit_code=$?
    
    if [[ $exit_code -eq 0 || $exit_code -eq 1 ]]; then
        COMMAND_CACHE["$cache_key"]="$result"
        COMMAND_CACHE_TIMESTAMP["$cache_key"]="$current_time"
        echo "$result"
    fi
    
    return $exit_code
}

# Optimized server counting
fast_server_count() {
    local file="$1"
    
    if [[ ! -f "$file" ]]; then
        echo "0"
        return 0
    fi
    
    # Use wc -l for fast line counting
    local count=$(wc -l < "$file" 2>/dev/null | tr -d ' ')
    count=${count:-0}
    
    # Ensure it's numeric
    if [[ "$count" =~ ^[0-9]+$ ]]; then
        echo "$count"
    else
        echo "0"
    fi
}

# Optimized array operations
fast_array_search() {
    local search_term="$1"
    shift
    local array=("$@")
    
    # Use built-in array operations
    for element in "${array[@]}"; do
        if [[ "$element" == *"$search_term"* ]]; then
            echo "$element"
            return 0
        fi
    done
    
    return 1
}

# Optimized string operations
fast_string_replace() {
    local string="$1"
    local search="$2"
    local replace="$3"
    
    # Use built-in parameter expansion for better performance
    echo "${string//$search/$replace}"
}

# Optimized directory listing
fast_dir_list() {
    local dir="$1"
    local pattern="${2:-*}"
    
    if [[ ! -d "$dir" ]]; then
        return 1
    fi
    
    # Use built-in globbing for better performance
    local files=()
    for file in "$dir"/$pattern; do
        [[ -e "$file" ]] && files+=("$(basename "$file")")
    done
    
    printf '%s\n' "${files[@]}"
}

# Track performance
track_performance() {
    local operation="$1"
    PERFORMANCE_STATS[operations]=$((${PERFORMANCE_STATS[operations]} + 1))
    log_event "PERFORMANCE" "Operation: $operation, Total: ${PERFORMANCE_STATS[operations]}"
}

# Show performance statistics
show_performance_stats() {
    local end_time=$(date +%s)
    local duration=$((end_time - ${PERFORMANCE_STATS[start_time]}))
    
    echo -e "\n${BLUE}=== Performance Statistics ===${NC}"
    echo -e "${CYAN}Session Duration:${NC} ${duration} seconds"
    echo -e "${CYAN}Total Operations:${NC} ${PERFORMANCE_STATS[operations]}"
    echo -e "${CYAN}Cache Hits:${NC} ${PERFORMANCE_STATS[cache_hits]}"
    echo -e "${CYAN}Cache Misses:${NC} ${PERFORMANCE_STATS[cache_misses]}"
    
    if [[ ${PERFORMANCE_STATS[operations]} -gt 0 ]]; then
        local ops_per_sec=$(echo "scale=2; ${PERFORMANCE_STATS[operations]} / $duration" | bc 2>/dev/null || echo "0")
        echo -e "${CYAN}Operations/Second:${NC} $ops_per_sec"
    fi
    
    if [[ $((${PERFORMANCE_STATS[cache_hits]} + ${PERFORMANCE_STATS[cache_misses]})) -gt 0 ]]; then
        local cache_hit_rate=$(echo "scale=1; ${PERFORMANCE_STATS[cache_hits]} * 100 / (${PERFORMANCE_STATS[cache_hits]} + ${PERFORMANCE_STATS[cache_misses]})" | bc 2>/dev/null || echo "0")
        echo -e "${CYAN}Cache Hit Rate:${NC} ${cache_hit_rate}%"
    fi
}

# Simple elegant banner
banner() {
    # Fixed width for consistent display
    local banner_width=76
    local border_line=$(printf '═%.0s' $(seq 1 $banner_width))
    
    echo -e "${CYAN}"
    echo "    ╔${border_line}╗"
    echo "    ║$(printf '%*s' $banner_width '')║"
    
    # Title line - center text without emojis first, then add them
    local title_text="SSH Vault Manager v${SVM_VERSION}"
    local title_display="🔐 ${title_text} 🔐"
    # Account for emoji display: text length + 2 spaces + 4 (2 emojis * 2 display chars each)
    local title_visual_len=$((${#title_text} + 2 + 4))
    local title_pad=$(( (banner_width - title_visual_len) / 2 ))
    
    printf "    ║%*s🔐 %s 🔐%*s║\n" \
        $title_pad "" \
        "$title_text" \
        $((banner_width - title_visual_len - title_pad)) ""
    
    echo "    ║$(printf '%*s' $banner_width '')║"
    
    # Subtitle line
    local subtitle="Secure • Fast • Reliable • Multi-Vault"
    local subtitle_len=${#subtitle}
    local subtitle_pad=$(( (banner_width - subtitle_len) / 2 ))
    
    printf "    ║%*s%s%*s║\n" \
        $subtitle_pad "" \
        "$subtitle" \
        $((banner_width - subtitle_len - subtitle_pad)) ""
    
    echo "    ║$(printf '%*s' $banner_width '')║"
    echo "    ╚${border_line}╝"
    echo -e "${NC}"
    
    if [[ -n "$current_vault_name" ]]; then
        echo -e "${CYAN}Current Vault: ${GREEN}$current_vault_name${NC}"
    else
        echo -e "${YELLOW}No vault selected - Use 'V' for Vault Management${NC}"
    fi
    echo
}

# Continue or exit helper
continue_or_exit() {
    echo
    read -p "Press Enter to continue or 'q' to quit: " choice
    if [[ "$choice" == "q" || "$choice" == "Q" ]]; then
        cleanup
    fi
}

# Continue or exit helper for vault menu
continue_or_exit_vault_menu() {
    echo
    read -p "Press Enter to continue or 'q' to quit: " choice
    if [[ "$choice" == "q" || "$choice" == "Q" ]]; then
        cleanup
        return 0
    fi
} 