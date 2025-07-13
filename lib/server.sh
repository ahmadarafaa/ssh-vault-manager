#!/bin/bash

# ============================================================================
# SERVER MANAGEMENT MODULE
# ============================================================================

# Add a new server to the vault
add_server() {
    local box_width=62
    local border
    border=$(printf '═%.0s' $(seq 1 $box_width))

    #
    # ── Banner: Add New Server ─────────────────────────────────────────────────
    #
    local raw_title=" Add New Server"
    local emoji="🔧"
    local title_text="$emoji$raw_title"
    # count non-ASCII (emoji) chars for proper centering
    local nonascii="${title_text//[ -~]/}"
    local nonascii_count=${#nonascii}
    local total_chars=${#title_text}
    local display_len=$(( total_chars + nonascii_count ))
    local pad_left=$(( (box_width - display_len) / 2 ))
    local pad_right=$(( box_width - pad_left - display_len ))

    echo -e "\n${CYAN}╔${border}╗${NC}"
    printf "${CYAN}║%*s${GREEN}%s${CYAN}%*s║${NC}\n" \
        $pad_left "" "$title_text" $pad_right ""
    echo -e "${CYAN}╚${border}╝${NC}"

    #
    # ── Prompt for server details ───────────────────────────────────────────────
    #
    echo -e "\n${YELLOW}📝 Enter Server Details:${NC}"
    printf "${BLUE}Name:${NC} ";       read name

    # IP validation loop
    while true; do
        printf "${BLUE}IP Address:${NC} "; read ip
        if [[ -z "$ip" ]]; then
            echo -e "${RED}❌ IP address cannot be empty.${NC}"; continue
        fi
        if ! [[ "$ip" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
            echo -e "${RED}❌ Invalid IP format.${NC}"; continue
        fi
        IFS='.' read -r -a parts <<< "$ip"
        local valid=true
        for p in "${parts[@]}"; do
            if (( p < 0 || p > 255 )); then
                valid=false; break
            fi
        done
        $valid || { echo -e "${RED}❌ IP parts must be between 0 and 255.${NC}"; continue; }
        break
    done

    printf "${BLUE}Username [root]:${NC} "; read username
    username="${username:-root}"

    # Port validation loop
    while true; do
        printf "${BLUE}Port [22]:${NC} "; read port
        port="${port:-22}"
        if ! [[ "$port" =~ ^[0-9]+$ ]] || (( port < 1 || port > 65535 )); then
            echo -e "${RED}❌ Port must be 1–65535.${NC}"; continue
        fi
        break
    done

    printf "${BLUE}Group:${NC} ";       read group
    printf "${BLUE}Info:${NC} ";        read additional_info

    # Password (masked)
    echo -e "\n${YELLOW}🔑 Authentication:${NC}"
    printf "${BLUE}Password:${NC} ";    read -s password; echo

    #
    # ── Prevent duplicates ─────────────────────────────────────────────────────
    #
    if [[ -f "$tmp_servers_file" ]]; then
        while IFS= read -r line; do
            [[ -z "$line" || "$line" =~ ^# ]] && continue
            IFS='|' read -r existing_name existing_ip existing_user existing_pass existing_port existing_group existing_info <<< "$line"

            if [[ "$existing_ip" == "$ip" ]]; then
                echo -e "\n${YELLOW}⚠ A server with IP ${existing_ip} already exists in the vault:${NC}"
                echo -e "   ${BLUE}Name:${NC}    ${existing_name}"
                echo -e "   ${BLUE}IP:${NC}      ${existing_ip}"
                echo -e "   ${BLUE}User:${NC}    ${existing_user}"
                echo -e "   ${BLUE}Port:${NC}    ${existing_port}"
                [[ -n "$existing_group" ]] && echo -e "   ${BLUE}Group:${NC}   ${existing_group}"
                [[ -n "$existing_info"  ]] && echo -e "   ${BLUE}Info:${NC}    ${existing_info}"
                return 1
            fi

            if [[ "$existing_name" == "$name" ]]; then
                echo -e "${YELLOW}⚠ A server named '${existing_name}' already exists with IP ${existing_ip}.${NC}"
                return 1
            fi
        done < "$tmp_servers_file"
    fi

    #
    # ── Append to vault and show success ────────────────────────────────────────
    #
    echo "$name|$ip|$username|$password|$port|$group|$additional_info" >> "$tmp_servers_file"

    # Success banner
    local raw_success="✅ Success!"
    local title_s="$raw_success"
    nonascii="${title_s//[ -~]/}"
    nonascii_count=${#nonascii}
    total_chars=${#title_s}
    display_len=$(( total_chars + nonascii_count ))
    pad_left=$(( (box_width - display_len) / 2 ))
    pad_right=$(( box_width - pad_left - display_len ))

    echo -e "\n${GREEN}╔${border}╗${NC}"
    printf "${GREEN}║%*s${CYAN}%s${GREEN}%*s║${NC}\n" \
        $pad_left "" "$title_s" $pad_right ""
    echo -e "${GREEN}╚${border}╝${NC}"

    # Final confirmation
    echo -e "\n${GREEN}🎉 Server '$name' added successfully!${NC}"
    echo -e "${CYAN}📊 Server Details:${NC}"
    echo -e "   ${BLUE}Name:${NC}     $name"
    echo -e "   ${BLUE}IP:${NC}       $ip"
    echo -e "   ${BLUE}Username:${NC} $username"
    echo -e "   ${BLUE}Port:${NC}     $port"
    [[ -n "$group"            ]] && echo -e "   ${BLUE}Group:${NC}    $group"
    [[ -n "$additional_info"  ]] && echo -e "   ${BLUE}Info:${NC}     $additional_info"

    log_event "SERVER_ADDED" "Server added: $name ($ip)" "$name|$ip"
    STATS[vault_operations]=$(( STATS[vault_operations] + 1 ))

    echo -e "\n${YELLOW}💡 Tip: Use 'List Servers' to view all servers in the vault.${NC}"
    return 0
}

# List servers in vault
list_servers() {
    if [[ ! -f "$tmp_servers_file" ]] || [[ ! -s "$tmp_servers_file" ]]; then
        echo -e "\n${YELLOW}No servers found in vault.${NC}"
        echo -e "${YELLOW}Use 'Add Server' to add your first server.${NC}"
        return 0
    fi

    echo -e "\n${GREEN}=== Server Inventory ===${NC}"
    
    # Get terminal width for responsive design
    local term_width=$(tput cols 2>/dev/null || echo 120)
    
    # Initialize minimum column widths (for headers)
    local name_w=4     # "Name"
    local ip_w=10      # "IP Address"
    local user_w=8     # "User"
    local port_w=4     # "Port"
    local group_w=5    # "Group"
    local info_w=4     # "Info"
    
    # First pass: scan all content to determine optimal column widths
    while IFS= read -r line || [[ -n "$line" ]]; do
        [[ -z "$line" || "$line" =~ ^# ]] && continue
        IFS='|' read -ra fields <<< "$line"
        local name="${fields[0]:-}"
        local ip="${fields[1]:-}"
        local username="${fields[2]:-}"
        local port="${fields[4]:-22}"
        local group="${fields[5]:-}"
        local info="${fields[6]:-}"
        
        # Calculate required widths
        [[ ${#name} -gt $name_w ]] && name_w=${#name}
        [[ ${#ip} -gt $ip_w ]] && ip_w=${#ip}
        [[ ${#username} -gt $user_w ]] && user_w=${#username}
        [[ ${#port} -gt $port_w ]] && port_w=${#port}
        [[ ${#group} -gt $group_w ]] && group_w=${#group}
        [[ ${#info} -gt $info_w ]] && info_w=${#info}
    done < "$tmp_servers_file"
    
    # Calculate total width needed and adjust if necessary
    local border_padding=7  # Account for | characters: │ │ │ │ │ │ │
    local total_content_width=$((name_w + ip_w + user_w + port_w + group_w + info_w))
    local total_table_width=$((total_content_width + border_padding))
    
    # If table is too wide for terminal, prioritize columns and adjust
    if [[ $total_table_width -gt $term_width ]]; then
        local available_width=$((term_width - border_padding))
        local excess=$((total_content_width - available_width))
        
        # Set maximum reasonable limits for each column
        local max_name_w=20
        local max_ip_w=15
        local max_user_w=15
        local max_port_w=6
        local max_group_w=15
        local max_info_w=50
        
        # Apply limits and recalculate
        [[ $name_w -gt $max_name_w ]] && name_w=$max_name_w
        [[ $ip_w -gt $max_ip_w ]] && ip_w=$max_ip_w
        [[ $user_w -gt $max_user_w ]] && user_w=$max_user_w
        [[ $port_w -gt $max_port_w ]] && port_w=$max_port_w
        [[ $group_w -gt $max_group_w ]] && group_w=$max_group_w
        [[ $info_w -gt $max_info_w ]] && info_w=$max_info_w
        
        # Recalculate and adjust info column if still too wide
        total_content_width=$((name_w + ip_w + user_w + port_w + group_w + info_w))
        if [[ $((total_content_width + border_padding)) -gt $term_width ]]; then
            local fixed_width=$((name_w + ip_w + user_w + port_w + group_w))
            info_w=$((term_width - border_padding - fixed_width))
            [[ $info_w -lt 10 ]] && info_w=10
        fi
    fi
    
    local server_count=0
    
    # Count servers
    while IFS= read -r line || [[ -n "$line" ]]; do
        [[ -z "$line" || "$line" =~ ^# ]] && continue
        ((server_count++))
    done < "$tmp_servers_file"
    
    echo -e "${BLUE}Total Servers: ${GREEN}$server_count${NC}\n"

    # Build table with optimized Info width
    printf "${CYAN}┌"
    printf '%0.s─' $(seq 1 $name_w); printf "┬"
    printf '%0.s─' $(seq 1 $ip_w); printf "┬"
    printf '%0.s─' $(seq 1 $user_w); printf "┬"
    printf '%0.s─' $(seq 1 $port_w); printf "┬"
    printf '%0.s─' $(seq 1 $group_w); printf "┬"
    printf '%0.s─' $(seq 1 $info_w); printf "┐${NC}\n"
    
    # Header row
    printf "${CYAN}│${YELLOW}%-*s${CYAN}│${YELLOW}%-*s${CYAN}│${YELLOW}%-*s${CYAN}│${YELLOW}%-*s${CYAN}│${YELLOW}%-*s${CYAN}│${YELLOW}%-*s${CYAN}│${NC}\n" \
        $name_w "Name" \
        $ip_w "IP Address" \
        $user_w "User" \
        $port_w "Port" \
        $group_w "Group" \
        $info_w "Info"
    
    # Header separator
    printf "${CYAN}├"
    printf '%0.s─' $(seq 1 $name_w); printf "┼"
    printf '%0.s─' $(seq 1 $ip_w); printf "┼"
    printf '%0.s─' $(seq 1 $user_w); printf "┼"
    printf '%0.s─' $(seq 1 $port_w); printf "┼"
    printf '%0.s─' $(seq 1 $group_w); printf "┼"
    printf '%0.s─' $(seq 1 $info_w); printf "┤${NC}\n"
    
    # Data rows
    local row_count=0
    local any_truncated=false
    while IFS= read -r line || [[ -n "$line" ]]; do
        [[ -z "$line" || "$line" =~ ^# ]] && continue
        IFS='|' read -ra fields <<< "$line"
        
        local name="${fields[0]:-}"
        local ip="${fields[1]:-}"
        local username="${fields[2]:-}"
        local port="${fields[4]:-22}"
        local group="${fields[5]:-}"
        local info="${fields[6]:-}"
        
        # Apply truncation only if content exceeds calculated width
        local display_name="$name"
        local display_ip="$ip"
        local display_user="$username"
        local display_port="$port"
        local display_group="$group"
        local display_info="$info"
        
        # Truncate only if necessary
        if [[ ${#display_name} -gt $name_w ]]; then
            display_name="${display_name:0:$((name_w-3))}..."
            any_truncated=true
        fi
        if [[ ${#display_ip} -gt $ip_w ]]; then
            display_ip="${display_ip:0:$((ip_w-3))}..."
            any_truncated=true
        fi
        if [[ ${#display_user} -gt $user_w ]]; then
            display_user="${display_user:0:$((user_w-3))}..."
            any_truncated=true
        fi
        if [[ ${#display_port} -gt $port_w ]]; then
            display_port="${display_port:0:$port_w}"
        fi
        if [[ ${#display_group} -gt $group_w ]]; then
            display_group="${display_group:0:$((group_w-3))}..."
            any_truncated=true
        fi
        if [[ ${#display_info} -gt $info_w ]]; then
            display_info="${display_info:0:$((info_w-3))}..."
            any_truncated=true
        fi
        
        # Print row with alternating colors
        if ((row_count % 2 == 0)); then
            printf "${CYAN}│${GREEN}%-*s${CYAN}│${GREEN}%-*s${CYAN}│${GREEN}%-*s${CYAN}│${GREEN}%-*s${CYAN}│${GREEN}%-*s${CYAN}│${GREEN}%-*s${CYAN}│${NC}\n" \
                $name_w "$display_name" \
                $ip_w "$display_ip" \
                $user_w "$display_user" \
                $port_w "$display_port" \
                $group_w "$display_group" \
                $info_w "$display_info"
        else
            printf "${CYAN}│${CYAN}%-*s${CYAN}│${CYAN}%-*s${CYAN}│${CYAN}%-*s${CYAN}│${CYAN}%-*s${CYAN}│${CYAN}%-*s${CYAN}│${CYAN}%-*s${CYAN}│${NC}\n" \
                $name_w "$display_name" \
                $ip_w "$display_ip" \
                $user_w "$display_user" \
                $port_w "$display_port" \
                $group_w "$display_group" \
                $info_w "$display_info"
        fi
        ((row_count++))
    done < "$tmp_servers_file"
    
    # Bottom border
    printf "${CYAN}└"
    printf '%0.s─' $(seq 1 $name_w); printf "┴"
    printf '%0.s─' $(seq 1 $ip_w); printf "┴"
    printf '%0.s─' $(seq 1 $user_w); printf "┴"
    printf '%0.s─' $(seq 1 $port_w); printf "┴"
    printf '%0.s─' $(seq 1 $group_w); printf "┴"
    printf '%0.s─' $(seq 1 $info_w); printf "┘${NC}\n"

    echo -e "\n${YELLOW}Tips:${NC}"
    echo "• Press '1' to connect to a server"
    echo "• Press '6' to search for servers"
    echo "• Press '2' to add a new server"
    
    # Show note about truncated content only if actually truncated
    if [[ "$any_truncated" == "true" ]]; then
        echo -e "${YELLOW}💡 Some Info content is truncated. Use 'Modify Server' to view full details.${NC}"
    fi
}

# Search servers in current vault
search_servers() {
    local search_term=""
    local no_prompt=false
    if [[ "$1" == "--no-prompt" ]]; then
        no_prompt=true
        search_term="$SEARCH_TERM_CLI"
    fi

    echo -e "\n${BLUE}=== Search Servers ===${NC}"

    if [[ ! -f "$tmp_servers_file" ]] || [[ ! -s "$tmp_servers_file" ]]; then
        echo -e "${YELLOW}No servers found in vault.${NC}"
        echo -e "${YELLOW}Use 'Add Server' to add your first server.${NC}"
        return 0
    fi

    if [[ "$no_prompt" == false ]]; then
        read -p "Enter search term: " search_term
    fi

    if [[ -z "$search_term" ]]; then
        echo -e "${RED}Search term cannot be empty.${NC}"
        return 1
    fi

    # Check rate limit for search
    if ! check_rate_limit "search"; then
        return 1
    fi

    local found_count=0
    local -a found_servers=()

    set +e
    while IFS= read -r line; do
        [[ -z "$line" || "$line" =~ ^# ]] && continue
        # Parse the line to get individual fields
        IFS='|' read -r name ip username password port group info <<< "$line"
        
        # Convert search term to lowercase for case-insensitive search
        search_term_lc="${search_term,,}"
        
        # Search in name, IP, and username fields
        if [[ "${name,,}" == *"$search_term_lc"* ]] || \
           [[ "${ip,,}" == *"$search_term_lc"* ]] || \
           [[ "${username,,}" == *"$search_term_lc"* ]]; then
            found_servers+=("$line")
            ((found_count++))
        fi
    done < "$tmp_servers_file"
    set -e

    # Get terminal width for responsive design
    local term_width=$(tput cols 2>/dev/null || echo 120)
    
    # Initialize minimum column widths (for headers)
    local num_w=1      # "#"
    local name_w=4     # "Name"
    local ip_w=10      # "IP Address"
    local user_w=8     # "Username"
    local port_w=4     # "Port"
    local group_w=5    # "Group"
    local info_w=4     # "Info"
    
    # First pass: scan all found content to determine optimal column widths
    for ((i=0; i<${#found_servers[@]}; i++)); do
        server_data="${found_servers[$i]}"
        IFS='|' read -r name ip username password port group additional_info <<< "$server_data"
        
        # Calculate required widths
        local num_len=${#found_count}
        [[ $((num_len + 1)) -gt $num_w ]] && num_w=$((num_len + 1))
        [[ ${#name} -gt $name_w ]] && name_w=${#name}
        [[ ${#ip} -gt $ip_w ]] && ip_w=${#ip}
        [[ ${#username} -gt $user_w ]] && user_w=${#username}
        [[ ${#port} -gt $port_w ]] && port_w=${#port}
        [[ ${#group} -gt $group_w ]] && group_w=${#group}
        [[ ${#additional_info} -gt $info_w ]] && info_w=${#additional_info}
    done
    
    # Calculate total width needed and adjust if necessary
    local border_padding=8  # Account for | characters: │ │ │ │ │ │ │ │
    local total_content_width=$((num_w + name_w + ip_w + user_w + port_w + group_w + info_w))
    local total_table_width=$((total_content_width + border_padding))
    
    # If table is too wide for terminal, prioritize columns and adjust
    if [[ $total_table_width -gt $term_width ]]; then
        local available_width=$((term_width - border_padding))
        local excess=$((total_content_width - available_width))
        
        # Set maximum reasonable limits for each column
        local max_name_w=20
        local max_ip_w=15
        local max_user_w=15
        local max_port_w=6
        local max_group_w=15
        local max_info_w=50
        
        # Apply limits and recalculate
        [[ $name_w -gt $max_name_w ]] && name_w=$max_name_w
        [[ $ip_w -gt $max_ip_w ]] && ip_w=$max_ip_w
        [[ $user_w -gt $max_user_w ]] && user_w=$max_user_w
        [[ $port_w -gt $max_port_w ]] && port_w=$max_port_w
        [[ $group_w -gt $max_group_w ]] && group_w=$max_group_w
        [[ $info_w -gt $max_info_w ]] && info_w=$max_info_w
        
        # Recalculate and adjust info column if still too wide
        total_content_width=$((num_w + name_w + ip_w + user_w + port_w + group_w + info_w))
        if [[ $((total_content_width + border_padding)) -gt $term_width ]]; then
            local fixed_width=$((num_w + name_w + ip_w + user_w + port_w + group_w))
            info_w=$((term_width - border_padding - fixed_width))
            [[ $info_w -lt 10 ]] && info_w=10
        fi
    fi

    # Build table header with dynamic widths
    printf "${CYAN}┌"
    printf '%0.s─' $(seq 1 $num_w); printf "┬"
    printf '%0.s─' $(seq 1 $name_w); printf "┬"
    printf '%0.s─' $(seq 1 $ip_w); printf "┬"
    printf '%0.s─' $(seq 1 $user_w); printf "┬"
    printf '%0.s─' $(seq 1 $port_w); printf "┬"
    printf '%0.s─' $(seq 1 $group_w); printf "┬"
    printf '%0.s─' $(seq 1 $info_w); printf "┐${NC}\n"
    
    # Header row
    printf "${CYAN}│${YELLOW}%-*s${CYAN}│${YELLOW}%-*s${CYAN}│${YELLOW}%-*s${CYAN}│${YELLOW}%-*s${CYAN}│${YELLOW}%-*s${CYAN}│${YELLOW}%-*s${CYAN}│${YELLOW}%-*s${CYAN}│${NC}\n" \
        $num_w "#" \
        $name_w "Name" \
        $ip_w "IP Address" \
        $user_w "Username" \
        $port_w "Port" \
        $group_w "Group" \
        $info_w "Info"
    
    # Header separator
    printf "${CYAN}├"
    printf '%0.s─' $(seq 1 $num_w); printf "┼"
    printf '%0.s─' $(seq 1 $name_w); printf "┼"
    printf '%0.s─' $(seq 1 $ip_w); printf "┼"
    printf '%0.s─' $(seq 1 $user_w); printf "┼"
    printf '%0.s─' $(seq 1 $port_w); printf "┼"
    printf '%0.s─' $(seq 1 $group_w); printf "┼"
    printf '%0.s─' $(seq 1 $info_w); printf "┤${NC}\n"

    if [[ $found_count -eq 0 ]]; then
        # Bottom border for no results
        printf "${CYAN}└"
        printf '%0.s─' $(seq 1 $num_w); printf "┴"
        printf '%0.s─' $(seq 1 $name_w); printf "┴"
        printf '%0.s─' $(seq 1 $ip_w); printf "┴"
        printf '%0.s─' $(seq 1 $user_w); printf "┴"
        printf '%0.s─' $(seq 1 $port_w); printf "┴"
        printf '%0.s─' $(seq 1 $group_w); printf "┴"
        printf '%0.s─' $(seq 1 $info_w); printf "┘${NC}\n"
        echo -e "\n${YELLOW}No servers found matching '$search_term'.${NC}"
        echo -e "${YELLOW}💡 Try a different search term or check spelling.${NC}"
        return 0
    else
        # Display server data with dynamic widths
        local any_truncated=false
        for ((i=0; i<${#found_servers[@]}; i++)); do
            server_data="${found_servers[$i]}"
            IFS='|' read -r name ip username password port group additional_info <<< "$server_data"
            
            # Apply truncation only if content exceeds calculated width
            local display_name="$name"
            local display_ip="$ip"
            local display_user="$username"
            local display_port="$port"
            local display_group="$group"
            local display_info="$additional_info"
            
            # Truncate only if necessary
            if [[ ${#display_name} -gt $name_w ]]; then
                display_name="${display_name:0:$((name_w-3))}..."
                any_truncated=true
            fi
            if [[ ${#display_ip} -gt $ip_w ]]; then
                display_ip="${display_ip:0:$((ip_w-3))}..."
                any_truncated=true
            fi
            if [[ ${#display_user} -gt $user_w ]]; then
                display_user="${display_user:0:$((user_w-3))}..."
                any_truncated=true
            fi
            if [[ ${#display_port} -gt $port_w ]]; then
                display_port="${display_port:0:$port_w}"
            fi
            if [[ ${#display_group} -gt $group_w ]]; then
                display_group="${display_group:0:$((group_w-3))}..."
                any_truncated=true
            fi
            if [[ ${#display_info} -gt $info_w ]]; then
                display_info="${display_info:0:$((info_w-3))}..."
                any_truncated=true
            fi
            
            # Display in table format with alternating colors
            if ((i % 2 == 0)); then
                printf "${CYAN}│${GREEN}%-*s${CYAN}│${GREEN}%-*s${CYAN}│${GREEN}%-*s${CYAN}│${GREEN}%-*s${CYAN}│${GREEN}%-*s${CYAN}│${GREEN}%-*s${CYAN}│${GREEN}%-*s${CYAN}│${NC}\n" \
                    $num_w "$((i + 1))" \
                    $name_w "$display_name" \
                    $ip_w "$display_ip" \
                    $user_w "$display_user" \
                    $port_w "$display_port" \
                    $group_w "$display_group" \
                    $info_w "$display_info"
            else
                printf "${CYAN}│${CYAN}%-*s${CYAN}│${CYAN}%-*s${CYAN}│${CYAN}%-*s${CYAN}│${CYAN}%-*s${CYAN}│${CYAN}%-*s${CYAN}│${CYAN}%-*s${CYAN}│${CYAN}%-*s${CYAN}│${NC}\n" \
                    $num_w "$((i + 1))" \
                    $name_w "$display_name" \
                    $ip_w "$display_ip" \
                    $user_w "$display_user" \
                    $port_w "$display_port" \
                    $group_w "$display_group" \
                    $info_w "$display_info"
            fi
        done
        
        # Bottom border
        printf "${CYAN}└"
        printf '%0.s─' $(seq 1 $num_w); printf "┴"
        printf '%0.s─' $(seq 1 $name_w); printf "┴"
        printf '%0.s─' $(seq 1 $ip_w); printf "┴"
        printf '%0.s─' $(seq 1 $user_w); printf "┴"
        printf '%0.s─' $(seq 1 $port_w); printf "┴"
        printf '%0.s─' $(seq 1 $group_w); printf "┴"
        printf '%0.s─' $(seq 1 $info_w); printf "┘${NC}\n"
        echo -e "\n${GREEN}Found:${NC} $found_count server(s)"
        
        # Show truncation message only if actually truncated
        if [[ "$any_truncated" == "true" ]]; then
            echo -e "${YELLOW}💡 Some content is truncated due to terminal width constraints.${NC}"
        fi
        
        # If called with --no-prompt (command line), show server selection
        if [[ "$no_prompt" == true ]]; then
            echo -e "\n${YELLOW}💡 Select a server number to connect:${NC}"
            read -p "Enter server number: " server_num
            if ! [[ "$server_num" =~ ^[0-9]+$ ]] || ((server_num < 1)) || ((server_num > found_count)); then
                echo -e "\n${RED}Invalid selection.${NC}"
                return 1
            fi
            
            local selected_index=$((server_num-1))
            local selected_server="${found_servers[$selected_index]}"
            IFS='|' read -r name ip username password port group additional_info <<< "$selected_server"
            
            echo -e "\n${CYAN}Connecting...${NC}"
            echo -e "\n${BLUE}Connecting to ${GREEN}$name${BLUE} (${GREEN}$ip${BLUE})...${NC}"
            
            # Update statistics
            STATS[connections_attempted]=$((${STATS[connections_attempted]} + 1))
            
            # Log connection attempt
            log_event "CONNECTION_ATTEMPT" "Connecting to $name ($ip) from per-vault search" "$name|$ip"
            
            # Check if sshpass is available
            if ! command -v sshpass >/dev/null 2>&1; then
                echo -e "\n${RED}Error: 'sshpass' is required for automatic password authentication${NC}"
                echo -e "${YELLOW}Please install sshpass:${NC}"
                echo -e "  Ubuntu/Debian: sudo apt-get install sshpass"
                echo -e "  CentOS/RHEL: sudo yum install sshpass"
                echo -e "  Or connect manually using: ssh -p $port $username@$ip"
                STATS[connections_failed]=$((${STATS[connections_failed]} + 1))
                log_event "CONNECTION_FAILED" "sshpass not available for $name ($ip)" "$name|$ip"
                return 1
            fi
            
            # Attempt SSH connection with stored password
            if sshpass -p "$password" ssh -p "$port" -o ConnectTimeout="${CONFIG[CONNECTION_TIMEOUT]}" -o StrictHostKeyChecking=no "$username@$ip"; then
                echo -e "\n${GREEN}Connection Successful${NC}"
                STATS[connections_successful]=$((${STATS[connections_successful]} + 1))
                log_event "CONNECTION_SUCCESS" "Successfully connected to $name ($ip) via per-vault search" "$name|$ip"
            else
                echo -e "\n${RED}SSH connection to $name failed.${NC}"
                echo -e "${YELLOW}Possible reasons:${NC}"
                echo -e "  - Server is not accessible"
                echo -e "  - SSH service is not running"
                echo -e "  - Firewall blocking connection"
                STATS[connections_failed]=$((${STATS[connections_failed]} + 1))
                log_event "CONNECTION_FAILED" "SSH connection failed for $name ($ip) via per-vault search" "$name|$ip"
                return 1
            fi
            
            # Exit script after SSH connection ends
            echo -e "\n${BLUE}SSH session ended. Exiting SSH Vault Manager.${NC}"
            cleanup
            exit 0
        else
            # Interactive mode - show tips
            echo -e "\n${YELLOW}Tips:${NC}"
            echo "• Press '1' to connect to a server"
            echo "• Press '5' to view all servers"
            echo "• Press '2' to add a new server"
        fi
    fi

    # Update rate limit
    update_rate_limit "search"
    return 0
}

# Connect to server
connect() {
    echo -e "\n${BLUE}=== Connect to Server ===${NC}"
    
    if [[ ! -f "$tmp_servers_file" ]] || [[ ! -s "$tmp_servers_file" ]]; then
        echo -e "${YELLOW}No servers found in vault.${NC}"
        return 0
    fi
    
    # Show server list for selection
    local servers=()
    local i=1
    echo -e "${CYAN}Available servers:${NC}"
    while IFS= read -r line; do
        [[ -z "$line" || "$line" =~ ^# ]] && continue
        IFS='|' read -r name ip username password port group additional_info <<< "$line"
        echo "  $i. $name ($ip)"
        servers+=("$line")
        ((i++))
    done < "$tmp_servers_file"
    
    read -p "Enter server number: " server_num
    if ! [[ "$server_num" =~ ^[0-9]+$ ]] || ((server_num < 1)) || ((server_num > ${#servers[@]})); then
        echo -e "${RED}Invalid selection.${NC}"
        return 1
    fi
    
    local selected_server="${servers[$((server_num-1))]}"
    IFS='|' read -r name ip username password port group additional_info <<< "$selected_server"
    
    echo -e "\n${GREEN}Connecting to $name ($ip)...${NC}"
    
    # Update statistics
    STATS[connections_attempted]=$((${STATS[connections_attempted]} + 1))
    
    # Log connection attempt
    log_event "CONNECTION_ATTEMPT" "Attempting connection to $name ($ip)" "$name|$ip"
    
    # Test connectivity first
    if ! secure_network_operation "test_connectivity" "$ip" "$port" "${CONFIG[CONNECTION_TIMEOUT]}"; then
        echo -e "${RED}Failed to connect to $ip:$port. Check network connectivity.${NC}"
        STATS[connections_failed]=$((${STATS[connections_failed]} + 1))
        log_event "CONNECTION_FAILED" "Network connectivity failed for $name ($ip)" "$name|$ip"
        return 1
    fi
    
    # Check if sshpass is available
    if ! command -v sshpass >/dev/null 2>&1; then
        echo -e "${RED}Error: 'sshpass' is required for automatic password authentication${NC}"
        echo -e "${YELLOW}Please install sshpass:${NC}"
        echo -e "  Ubuntu/Debian: sudo apt-get install sshpass"
        echo -e "  CentOS/RHEL: sudo yum install sshpass"
        echo -e "  Or connect manually using: ssh -p $port $username@$ip"
        STATS[connections_failed]=$((${STATS[connections_failed]} + 1))
        log_event "CONNECTION_FAILED" "sshpass not available for $name ($ip)" "$name|$ip"
        return 1
    fi
    
    # Attempt SSH connection with stored password
    if sshpass -p "$password" ssh -p "$port" -o ConnectTimeout="${CONFIG[CONNECTION_TIMEOUT]}" -o StrictHostKeyChecking=no "$username@$ip"; then
        echo -e "${GREEN}Connection to $name completed successfully.${NC}"
        STATS[connections_successful]=$((${STATS[connections_successful]} + 1))
        log_event "CONNECTION_SUCCESS" "Successfully connected to $name ($ip)" "$name|$ip"
    else
        echo -e "${RED}SSH connection to $name failed.${NC}"
        echo -e "${YELLOW}Possible reasons:${NC}"
        echo -e "  - Server is not accessible"
        echo -e "  - SSH service is not running"
        echo -e "  - Firewall blocking connection"
        STATS[connections_failed]=$((${STATS[connections_failed]} + 1))
        log_event "CONNECTION_FAILED" "SSH connection failed for $name ($ip)" "$name|$ip"
        return 1
    fi
    
    # Exit script after SSH connection ends
    echo -e "${BLUE}SSH session ended. Exiting SSH Vault Manager.${NC}"
    cleanup
    exit 0
}

# View connection logs
view_logs() {
    echo -e "\n${BLUE}=== Connection Logs & Statistics ===${NC}"
    
    if [[ -f "$log_file" ]]; then
        echo -e "${CYAN}Recent connection logs:${NC}"
        tail -n 20 "$log_file" | while IFS= read -r line; do
            if [[ "$line" == *"CONNECTION"* ]]; then
                if [[ "$line" == *"SUCCESS"* ]]; then
                    echo -e "${GREEN}$line${NC}"
                elif [[ "$line" == *"FAILED"* ]]; then
                    echo -e "${RED}$line${NC}"
                else
                    echo -e "${YELLOW}$line${NC}"
                fi
            else
                echo "$line"
            fi
        done
    else
        echo -e "${YELLOW}No log file found.${NC}"
    fi
    
    # Show current session statistics
    show_statistics
    
    return 0
}

# View security logs
view_security_logs() {
    local security_log="$base_vault_dir/.security.log"
    
    if [[ ! -f "$security_log" ]]; then
        echo -e "${YELLOW}No security logs found.${NC}"
        return 0
    fi
    
    echo -e "\n${BLUE}=== Security Logs ===${NC}"
    echo -e "${CYAN}Recent security events:${NC}"
    
    # Show last 20 security events with color coding
    tail -n 20 "$security_log" | while IFS= read -r line; do
        if [[ "$line" == *"[CRITICAL]"* ]]; then
            echo -e "${RED}$line${NC}"
        elif [[ "$line" == *"[WARNING]"* ]]; then
            echo -e "${YELLOW}$line${NC}"
        elif [[ "$line" == *"[ERROR]"* ]]; then
            echo -e "${MAGENTA}$line${NC}"
        elif [[ "$line" == *"[INFO]"* ]]; then
            echo -e "${GREEN}$line${NC}"
        else
            echo "$line"
        fi
    done
    
    # Show security statistics
    echo -e "\n${CYAN}Security Statistics:${NC}"
    local total_events=0
    local critical_events=0
    local warning_events=0
    local error_events=0
    
    # Safely get counts with proper error handling
    if [[ -f "$security_log" ]]; then
        total_events=$(wc -l < "$security_log" 2>/dev/null | tr -d ' ' || echo "0")
        critical_events=$(grep -c "\[CRITICAL\]" "$security_log" 2>/dev/null | tr -d ' ' || echo "0")
        warning_events=$(grep -c "\[WARNING\]" "$security_log" 2>/dev/null | tr -d ' ' || echo "0")
        error_events=$(grep -c "\[ERROR\]" "$security_log" 2>/dev/null | tr -d ' ' || echo "0")
    fi
    
    # Ensure all values are numeric
    total_events=${total_events:-0}
    critical_events=${critical_events:-0}
    warning_events=${warning_events:-0}
    error_events=${error_events:-0}
    
    echo -e "  Total Events: $total_events"
    echo -e "  Critical: ${RED}$critical_events${NC}"
    echo -e "  Warnings: ${YELLOW}$warning_events${NC}"
    echo -e "  Errors: ${MAGENTA}$error_events${NC}"
    
    if [[ $critical_events -gt 0 ]]; then
        echo -e "\n${RED}⚠️  CRITICAL SECURITY EVENTS DETECTED!${NC}"
        echo -e "Please review the security log for details."
    fi
}

# Remove server from vault
remove_server() {
    # ── Setup box dimensions to match your table (interior width = 81 chars)
    local box_width=81
    local box_border
    box_border=$(printf '═%.0s' $(seq 1 $box_width))

    # ── Banner: Remove Server
    echo -e "\n${CYAN}╔${box_border}╗${NC}"
    local title_text="🗑  Remove Server"
    local text_len=${#title_text}
    local pad_left=$(( (box_width - text_len) / 2 ))
    printf "${CYAN}║%*s${RED}%s${NC}%*s${CYAN}║${NC}\n" \
        $pad_left "" "$title_text" $(( box_width - pad_left - text_len )) ""
    echo -e "${CYAN}╚${box_border}╝${NC}"

    # ── No‐servers guard
    if [[ ! -f "$tmp_servers_file" ]] || [[ ! -s "$tmp_servers_file" ]]; then
        echo -e "\n${YELLOW}No servers found in vault.${NC}"
        echo -e "${YELLOW}Use 'Add Server' to add your first server.${NC}"
        return 0
    fi

    # ── Backup current vault
    local backup_file="$vault/${CONFIG[BACKUP_PREFIX]}_$(date +%Y%m%d_%H%M%S).enc"
    echo -e "\n${BLUE}📦 Creating backup before removal...${NC}"
    if encrypt_vault "$tmp_servers_file" "$backup_file"; then
        echo -e "${GREEN}✅ Backup created: $(basename "$backup_file")${NC}"
        log_event "BACKUP_CREATED" "Backup created before server removal: $backup_file"
    else
        echo -e "${RED}❌ Failed to create backup. Aborting removal.${NC}"
        return 1
    fi

    # ── Load & display all servers
    local server_count=0
    local servers=() server_names=() server_ips=() server_users=() server_ports=() server_groups=()
    while IFS= read -r line; do
        [[ -z "$line" || "$line" =~ ^# ]] && continue
        IFS='|' read -r name ip username password port group <<< "$line"
        servers+=("$line")
        server_names+=("$name")
        server_ips+=("$ip")
        server_users+=("$username")
        server_ports+=("$port")
        server_groups+=("$group")
        ((server_count++))
    done < "$tmp_servers_file"

    echo -e "\n${YELLOW}📋 Available servers:${NC}"
    echo -e "${CYAN}┌─────┬─────────────────┬───────────────────┬──────────────┬───────┬──────────────┐${NC}"
    printf "${CYAN}│ ${GREEN}%3s${CYAN} │ ${GREEN}%-15s${CYAN} │ ${GREEN}%-17s${CYAN} │ ${GREEN}%-12s${CYAN} │ ${GREEN}%5s${CYAN} │ ${GREEN}%-12s${CYAN} │${NC}\n" \
        "#" "Name" "IP Address" "Username" "Port" "Group"
    echo -e "${CYAN}├─────┼─────────────────┼───────────────────┼──────────────┼───────┼──────────────┤${NC}"
    for i in "${!servers[@]}"; do
        printf "${CYAN}│ ${CYAN}%3s${CYAN} │ ${CYAN}%-15s${CYAN} │ ${CYAN}%-17s${CYAN} │ ${CYAN}%-12s${CYAN} │ ${CYAN}%5s${CYAN} │ ${CYAN}%-12s${CYAN} │${NC}\n" \
            $((i+1)) "${server_names[i]:0:15}" "${server_ips[i]:0:17}" "${server_users[i]:0:12}" "${server_ports[i]:0:5}" "${server_groups[i]:0:12}"
    done
    echo -e "${CYAN}└─────┴─────────────────┴───────────────────┴──────────────┴───────┴──────────────┘${NC}"
    echo -e "\n${BLUE}Total servers: ${GREEN}${server_count}${NC}"

    # ── Prompt for which to remove
    read -p "Enter server number to remove (or 'c' to cancel): " selection
    if [[ "$selection" =~ ^[cC]$ ]]; then
        echo -e "${BLUE}Operation cancelled.${NC}"
        return 0
    fi
    if ! [[ "$selection" =~ ^[0-9]+$ ]] || (( selection < 1 || selection > server_count )); then
        echo -e "${RED}❌ Invalid selection. Please enter a number between 1 and ${server_count}.${NC}"
        return 1
    fi

    local sel_idx=$((selection - 1))
    IFS='|' read -r selected_name selected_ip selected_user _ selected_port selected_group <<< "${servers[$sel_idx]}"

    # ── Banner: Confirm Removal
    echo -e "\n${RED}╔${box_border}╗${NC}"
    local confirm_text="⚠  CONFIRM REMOVAL"
    local confirm_len=${#confirm_text}
    local confirm_pad=$(( (box_width - confirm_len) / 2 ))
    printf "${RED}║%*s${YELLOW}%s${NC}%*s${RED}║${NC}\n" \
        $confirm_pad "" "$confirm_text" $(( box_width - confirm_pad - confirm_len )) ""
    echo -e "${RED}╚${box_border}╝${NC}"

    echo -e "\n${YELLOW}You are about to remove:${NC}"
    echo -e "   ${BLUE}Name:${NC} ${selected_name}"
    echo -e "   ${BLUE}IP:${NC} ${selected_ip}"
    echo -e "   ${BLUE}Username:${NC} ${selected_user}"
    echo -e "   ${BLUE}Port:${NC} ${selected_port}"
    [[ -n "${selected_group}" ]] && echo -e "   ${BLUE}Group:${NC} ${selected_group}"
    echo -e "\n${RED}This action cannot be undone!${NC}"
    read -p "To confirm removal, type the exact server name: " confirmation
    if [[ "$confirmation" != "$selected_name" ]]; then
        echo -e "${BLUE}Operation cancelled.${NC}"
        return 0
    fi

    # ── Perform the removal
    local new_tmp_file
    new_tmp_file=$(create_svm_temp_file 'remove')
    chmod 600 "$new_tmp_file"
    local line_no=0
    while IFS= read -r line; do
        [[ -z "$line" || "$line" =~ ^# ]] && continue
        (( line_no++ ))
        [[ $line_no -eq $selection ]] && continue
        echo "$line" >> "$new_tmp_file"
    done < "$tmp_servers_file"
    mv "$new_tmp_file" "$tmp_servers_file"
    chmod 600 "$tmp_servers_file"

    # ── Banner: Success
    echo -e "\n${GREEN}╔${box_border}╗${NC}"
    local success_text="✅ SUCCESS!"
    local success_len=${#success_text}
    local success_pad=$(( (box_width - success_len) / 2 ))
    printf "${GREEN}║%*s${CYAN}%s${NC}%*s${GREEN}║${NC}\n" \
        $success_pad "" "$success_text" $(( box_width - success_pad - success_len )) ""
    echo -e "${GREEN}╚${box_border}╝${NC}"

    echo -e "\n${GREEN}🎉 Server '${selected_name}' removed successfully!${NC}"
    echo -e "${CYAN}📊 Removed Details:${NC}"
    echo -e "   ${BLUE}Name:${NC} ${selected_name}"
    echo -e "   ${BLUE}IP:${NC} ${selected_ip}"
    echo -e "   ${BLUE}Username:${NC} ${selected_user}"
    echo -e "   ${BLUE}Port:${NC} ${selected_port}"
    [[ -n "${selected_group}" ]] && echo -e "   ${BLUE}Group:${NC} ${selected_group}"

    # ── Final housekeeping
    echo -e "\n${YELLOW}💾 Backup saved as: $(basename "$backup_file")${NC}"
    log_event "SERVER_REMOVED" "Server removed: $selected_name ($selected_ip)" "$selected_name|$selected_ip"
    STATS[vault_operations]=$(( STATS[vault_operations] + 1 ))
    echo -e "\n${YELLOW}💡 Tip: Use 'List Servers' to view remaining servers in the vault.${NC}"

    return 0
}

# Modify server in vault
modify_server() {
    local box_width=64
    local border=$(printf '═%.0s' $(seq 1 $box_width))
    echo -e "\n${CYAN}╔${border}╗${NC}"
    
    # Title with emoji - account for emoji display width
    local title_text="Modify Server"
    local emoji="🔧"
    # Text length + 1 space + 2 (emoji display width)
    local visual_len=$((${#title_text} + 1 + 2))
    local padding=$(( (box_width - visual_len) / 2 ))
    
    printf "${CYAN}║%*s${BLUE}%s %s${CYAN}%*s║${NC}\n" \
        $padding "" \
        "$emoji" "$title_text" \
        $((box_width - visual_len - padding)) ""
    
    echo -e "${CYAN}╚${border}╝${NC}"

    if [[ ! -f "$tmp_servers_file" ]] || [[ ! -s "$tmp_servers_file" ]]; then
        echo -e "\n${YELLOW}No servers found in vault.${NC}"
        echo -e "${YELLOW}Use 'Add Server' to add your first server.${NC}"
        return 0
    fi

    # Create backup before modification
    local backup_file="$vault/${CONFIG[BACKUP_PREFIX]}_$(date +%Y%m%d_%H%M%S).enc"
    echo -e "\n${BLUE}📦 Creating backup before modification...${NC}"
    
    if encrypt_vault "$tmp_servers_file" "$backup_file"; then
        echo -e "${GREEN}✅ Backup created: $(basename "$backup_file")${NC}"
        log_event "BACKUP_CREATED" "Backup created before server modification: $backup_file"
    else
        echo -e "${RED}❌ Failed to create backup. Aborting modification.${NC}"
        return 1
    fi

    # Count and display servers with fully dynamic table formatting
    local server_count=0
    local servers=()
    local server_names=()
    local server_ips=()
    local server_users=()
    local server_ports=()
    local server_groups=()
    local server_passwords=()
    local server_infos=()

    echo -e "\n${YELLOW}📋 Available servers:${NC}"
    
    # Get terminal width for responsive design
    local term_width=$(tput cols 2>/dev/null || echo 120)
    
    # Initialize minimum column widths (for headers)
    local num_w=1      # "#"
    local name_w=4     # "Name"
    local ip_w=10      # "IP Address"
    local user_w=8     # "Username"
    local port_w=4     # "Port"
    local group_w=5    # "Group"
    local info_w=4     # "Info"
    
    # First pass: scan all content to determine optimal column widths
    while IFS= read -r line; do
        [[ -z "$line" || "$line" =~ ^# ]] && continue
        IFS='|' read -r name ip username password port group additional_info <<< "$line"
        
        # Store server data
        servers+=("$line")
        server_names+=("$name")
        server_ips+=("$ip")
        server_users+=("$username")
        server_ports+=("$port")
        server_groups+=("$group")
        server_passwords+=("$password")
        server_infos+=("$additional_info")
        
        # Calculate required widths
        local num_len=${#server_count}
        [[ $((num_len + 1)) -gt $num_w ]] && num_w=$((num_len + 1))
        [[ ${#name} -gt $name_w ]] && name_w=${#name}
        [[ ${#ip} -gt $ip_w ]] && ip_w=${#ip}
        [[ ${#username} -gt $user_w ]] && user_w=${#username}
        [[ ${#port} -gt $port_w ]] && port_w=${#port}
        [[ ${#group} -gt $group_w ]] && group_w=${#group}
        [[ ${#additional_info} -gt $info_w ]] && info_w=${#additional_info}
        
        ((server_count++))
    done < "$tmp_servers_file"
    
    # Account for the final server number width
    local final_num_len=${#server_count}
    [[ $final_num_len -gt $num_w ]] && num_w=$final_num_len
    
    # Calculate total width needed and adjust if necessary
    local border_padding=8  # Account for | characters: │ │ │ │ │ │ │ │
    local total_content_width=$((num_w + name_w + ip_w + user_w + port_w + group_w + info_w))
    local total_table_width=$((total_content_width + border_padding))
    
    # If table is too wide for terminal, prioritize columns and adjust
    if [[ $total_table_width -gt $term_width ]]; then
        local available_width=$((term_width - border_padding))
        local excess=$((total_content_width - available_width))
        
        # Set maximum reasonable limits for each column
        local max_name_w=20
        local max_ip_w=15
        local max_user_w=15
        local max_port_w=6
        local max_group_w=15
        local max_info_w=50
        
        # Apply limits and recalculate
        [[ $name_w -gt $max_name_w ]] && name_w=$max_name_w
        [[ $ip_w -gt $max_ip_w ]] && ip_w=$max_ip_w
        [[ $user_w -gt $max_user_w ]] && user_w=$max_user_w
        [[ $port_w -gt $max_port_w ]] && port_w=$max_port_w
        [[ $group_w -gt $max_group_w ]] && group_w=$max_group_w
        [[ $info_w -gt $max_info_w ]] && info_w=$max_info_w
        
        # Recalculate and adjust info column if still too wide
        total_content_width=$((num_w + name_w + ip_w + user_w + port_w + group_w + info_w))
        if [[ $((total_content_width + border_padding)) -gt $term_width ]]; then
            local fixed_width=$((num_w + name_w + ip_w + user_w + port_w + group_w))
            info_w=$((term_width - border_padding - fixed_width))
            [[ $info_w -lt 10 ]] && info_w=10
        fi
    fi

    # Build table header with dynamic widths
    printf "${CYAN}┌"
    printf '%0.s─' $(seq 1 $num_w); printf "┬"
    printf '%0.s─' $(seq 1 $name_w); printf "┬"
    printf '%0.s─' $(seq 1 $ip_w); printf "┬"
    printf '%0.s─' $(seq 1 $user_w); printf "┬"
    printf '%0.s─' $(seq 1 $port_w); printf "┬"
    printf '%0.s─' $(seq 1 $group_w); printf "┬"
    printf '%0.s─' $(seq 1 $info_w); printf "┐${NC}\n"
    
    # Header row
    printf "${CYAN}│${YELLOW}%-*s${CYAN}│${YELLOW}%-*s${CYAN}│${YELLOW}%-*s${CYAN}│${YELLOW}%-*s${CYAN}│${YELLOW}%-*s${CYAN}│${YELLOW}%-*s${CYAN}│${YELLOW}%-*s${CYAN}│${NC}\n" \
        $num_w "#" \
        $name_w "Name" \
        $ip_w "IP Address" \
        $user_w "Username" \
        $port_w "Port" \
        $group_w "Group" \
        $info_w "Info"
    
    # Header separator
    printf "${CYAN}├"
    printf '%0.s─' $(seq 1 $num_w); printf "┼"
    printf '%0.s─' $(seq 1 $name_w); printf "┼"
    printf '%0.s─' $(seq 1 $ip_w); printf "┼"
    printf '%0.s─' $(seq 1 $user_w); printf "┼"
    printf '%0.s─' $(seq 1 $port_w); printf "┼"
    printf '%0.s─' $(seq 1 $group_w); printf "┼"
    printf '%0.s─' $(seq 1 $info_w); printf "┤${NC}\n"

    # Display server data with dynamic widths
    local any_truncated=false
    for ((i=0; i<${#servers[@]}; i++)); do
        local name="${server_names[$i]}"
        local ip="${server_ips[$i]}"
        local username="${server_users[$i]}"
        local port="${server_ports[$i]}"
        local group="${server_groups[$i]}"
        local additional_info="${server_infos[$i]}"
        
        # Apply truncation only if content exceeds calculated width
        local display_name="$name"
        local display_ip="$ip"
        local display_user="$username"
        local display_port="$port"
        local display_group="$group"
        local display_info="$additional_info"
        
        # Truncate only if necessary
        if [[ ${#display_name} -gt $name_w ]]; then
            display_name="${display_name:0:$((name_w-3))}..."
            any_truncated=true
        fi
        if [[ ${#display_ip} -gt $ip_w ]]; then
            display_ip="${display_ip:0:$((ip_w-3))}..."
            any_truncated=true
        fi
        if [[ ${#display_user} -gt $user_w ]]; then
            display_user="${display_user:0:$((user_w-3))}..."
            any_truncated=true
        fi
        if [[ ${#display_port} -gt $port_w ]]; then
            display_port="${display_port:0:$port_w}"
        fi
        if [[ ${#display_group} -gt $group_w ]]; then
            display_group="${display_group:0:$((group_w-3))}..."
            any_truncated=true
        fi
        if [[ ${#display_info} -gt $info_w ]]; then
            display_info="${display_info:0:$((info_w-3))}..."
            any_truncated=true
        fi
        
        # Display in table format with alternating colors
        if ((i % 2 == 0)); then
            printf "${CYAN}│${GREEN}%-*s${CYAN}│${GREEN}%-*s${CYAN}│${GREEN}%-*s${CYAN}│${GREEN}%-*s${CYAN}│${GREEN}%-*s${CYAN}│${GREEN}%-*s${CYAN}│${GREEN}%-*s${CYAN}│${NC}\n" \
                $num_w "$((i + 1))" \
                $name_w "$display_name" \
                $ip_w "$display_ip" \
                $user_w "$display_user" \
                $port_w "$display_port" \
                $group_w "$display_group" \
                $info_w "$display_info"
        else
            printf "${CYAN}│${CYAN}%-*s${CYAN}│${CYAN}%-*s${CYAN}│${CYAN}%-*s${CYAN}│${CYAN}%-*s${CYAN}│${CYAN}%-*s${CYAN}│${CYAN}%-*s${CYAN}│${CYAN}%-*s${CYAN}│${NC}\n" \
                $num_w "$((i + 1))" \
                $name_w "$display_name" \
                $ip_w "$display_ip" \
                $user_w "$display_user" \
                $port_w "$display_port" \
                $group_w "$display_group" \
                $info_w "$display_info"
        fi
    done

    # Bottom border
    printf "${CYAN}└"
    printf '%0.s─' $(seq 1 $num_w); printf "┴"
    printf '%0.s─' $(seq 1 $name_w); printf "┴"
    printf '%0.s─' $(seq 1 $ip_w); printf "┴"
    printf '%0.s─' $(seq 1 $user_w); printf "┴"
    printf '%0.s─' $(seq 1 $port_w); printf "┴"
    printf '%0.s─' $(seq 1 $group_w); printf "┴"
    printf '%0.s─' $(seq 1 $info_w); printf "┘${NC}\n"

    echo -e "\n${BLUE}Total servers: ${GREEN}$server_count${NC}"

    if [[ $server_count -eq 0 ]]; then
        echo -e "\n${YELLOW}No servers to modify.${NC}"
        return 0
    fi

    # Show truncation message only if actually truncated
    if [[ "$any_truncated" == "true" ]]; then
        echo -e "${YELLOW}💡 Some content is truncated due to terminal width constraints.${NC}"
    fi

    # Get user selection
    read -p "Enter server number to modify (or 'c' to cancel): " selection

    # Handle cancellation
    if [[ "$selection" =~ ^[cC]$ ]]; then
        echo -e "\n${BLUE}Operation cancelled.${NC}"
        return 0
    fi

    # Validate selection
    if ! [[ "$selection" =~ ^[0-9]+$ ]] || ((selection < 1)) || ((selection > server_count)); then
        echo -e "\n${RED}❌ Invalid selection. Please enter a number between 1 and $server_count.${NC}"
        return 1
    fi

    # Get selected server details
    local selected_index=$((selection - 1))
    local current_name="${server_names[$selected_index]}"
    local current_ip="${server_ips[$selected_index]}"
    local current_user="${server_users[$selected_index]}"
    local current_port="${server_ports[$selected_index]}"
    local current_group="${server_groups[$selected_index]}"
    local current_password="${server_passwords[$selected_index]}"
    local current_info="${server_infos[$selected_index]}"

    # Show current details
    echo -e "\n${BLUE}╔${border}╗${NC}"
    
    # Current details title
    local details_title="Current Details"
    local details_emoji="📋"
    local details_visual_len=$((${#details_title} + 1 + 2))
    local details_padding=$(( (box_width - details_visual_len) / 2 ))
    
    printf "${BLUE}║%*s${YELLOW}%s %s${BLUE}%*s║${NC}\n" \
        $details_padding "" \
        "$details_emoji" "$details_title" \
        $((box_width - details_visual_len - details_padding)) ""
    
    echo -e "${BLUE}╚${border}╝${NC}"
    echo -e "\n${CYAN}Current server details:${NC}"
    echo -e "   ${BLUE}Name:${NC} $current_name"
    echo -e "   ${BLUE}IP:${NC} $current_ip"
    echo -e "   ${BLUE}Username:${NC} $current_user"
    echo -e "   ${BLUE}Port:${NC} $current_port"
    [[ -n "$current_group" ]] && echo -e "   ${BLUE}Group:${NC} $current_group"
    [[ -n "$current_info" ]] && echo -e "   ${BLUE}Info:${NC} $current_info"

    echo -e "\n${YELLOW}📝 Enter new details (press Enter to keep current value):${NC}"

    # Get new values with current values as defaults
    printf "${BLUE}Name [$current_name]:${NC} "
    read new_name
    new_name="${new_name:-$current_name}"

    # IP validation loop
    while true; do
        printf "${BLUE}IP Address [$current_ip]:${NC} "
        read new_ip
        new_ip="${new_ip:-$current_ip}"
        
        if [[ -z "$new_ip" ]]; then
            echo -e "${RED}❌ IP address cannot be empty.${NC}"
            continue
        fi
        if ! [[ "$new_ip" =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
            echo -e "${RED}❌ Invalid IP address format.${NC}"
            continue
        fi
        IFS='.' read -r -a ip_parts <<< "$new_ip"
        local valid_ip=true
        for part in "${ip_parts[@]}"; do
            if [[ $part -gt 255 ]]; then
                echo -e "${RED}❌ Invalid IP address: octets must be 0-255.${NC}"
                valid_ip=false
                break
            fi
        done
        if [[ "$valid_ip" == "true" ]]; then
            break
        fi
    done

    printf "${BLUE}Username [$current_user]:${NC} "
    read new_username
    new_username="${new_username:-$current_user}"

    # Port validation loop
    while true; do
        printf "${BLUE}Port [$current_port]:${NC} "
        read new_port
        new_port="${new_port:-$current_port}"
        
        if ! [[ "$new_port" =~ ^[0-9]+$ ]] || [[ $new_port -lt 1 ]] || [[ $new_port -gt 65535 ]]; then
            echo -e "${RED}❌ Invalid port number: must be 1-65535.${NC}"
            continue
        fi
        break
    done

    printf "${BLUE}Group [$current_group]:${NC} "
    read new_group
    new_group="${new_group:-$current_group}"

    printf "${BLUE}Info [$current_info]:${NC} "
    read new_info
    new_info="${new_info:-$current_info}"

    # Password prompt (separate, masked)
    echo -e "\n${YELLOW}🔑 Authentication:${NC}"
    printf "${BLUE}Password (press Enter to keep current):${NC} "
    read -s new_password
    echo
    new_password="${new_password:-$current_password}"

    # Validate remaining input
    if ! validate_and_sanitize_server_input "$new_name" "$new_ip" "$new_port" "$new_username"; then
        return 1
    fi

    # Check if new name conflicts with existing servers (excluding current)
    if [[ "$new_name" != "$current_name" ]]; then
        local line_number=0
        while IFS= read -r line; do
            [[ -z "$line" || "$line" =~ ^# ]] && continue
            ((line_number++))
            
            # Skip the current server being modified
            if [[ $line_number -eq $selection ]]; then
                continue
            fi
            
            IFS='|' read -r existing_name existing_ip existing_user existing_pass existing_port existing_group existing_info <<< "$line"
            if [[ "$existing_name" == "$new_name" ]]; then
                echo -e "\n${RED}❌ Server name '$new_name' already exists in the vault.${NC}"
                return 1
            fi
        done < "$tmp_servers_file"
    fi

    # Show summary of changes
    echo -e "\n${BLUE}╔${border}╗${NC}"
    
    # Changes summary title
    local changes_title="Changes Summary"
    local changes_emoji="📊"
    local changes_visual_len=$((${#changes_title} + 1 + 2))
    local changes_padding=$(( (box_width - changes_visual_len) / 2 ))
    
    printf "${BLUE}║%*s${YELLOW}%s %s${BLUE}%*s║${NC}\n" \
        $changes_padding "" \
        "$changes_emoji" "$changes_title" \
        $((box_width - changes_visual_len - changes_padding)) ""
    
    echo -e "${BLUE}╚${border}╝${NC}"
    echo -e "\n${CYAN}Changes to be applied:${NC}"
    
    if [[ "$new_name" != "$current_name" ]]; then
        echo -e "   ${BLUE}Name:${NC} $current_name → ${GREEN}$new_name${NC}"
    fi
    if [[ "$new_ip" != "$current_ip" ]]; then
        echo -e "   ${BLUE}IP:${NC} $current_ip → ${GREEN}$new_ip${NC}"
    fi
    if [[ "$new_username" != "$current_user" ]]; then
        echo -e "   ${BLUE}Username:${NC} $current_user → ${GREEN}$new_username${NC}"
    fi
    if [[ "$new_port" != "$current_port" ]]; then
        echo -e "   ${BLUE}Port:${NC} $current_port → ${GREEN}$new_port${NC}"
    fi
    if [[ "$new_group" != "$current_group" ]]; then
        echo -e "   ${BLUE}Group:${NC} $current_group → ${GREEN}$new_group${NC}"
    fi
    if [[ "$new_info" != "$current_info" ]]; then
        echo -e "   ${BLUE}Info:${NC} $current_info → ${GREEN}$new_info${NC}"
    fi
    if [[ "$new_password" != "$current_password" ]]; then
        echo -e "   ${BLUE}Password:${NC} [CHANGED]"
    fi

    # Confirm modification
    echo -e "\n${YELLOW}⚠️  Confirm these changes?${NC}"
    read -p "Type 'y', 'Y', or press Enter to confirm (or anything else to cancel): " confirmation

    if [[ ! "$confirmation" =~ ^[yY]?$ ]]; then
        echo -e "\n${BLUE}Operation cancelled.${NC}"
        return 0
    fi

    # Create new temporary file with the modified server
    local new_tmp_file=$(create_svm_temp_file 'modify')
    chmod 600 "$new_tmp_file"
    
    local line_number=0
    while IFS= read -r line; do
        [[ -z "$line" || "$line" =~ ^# ]] && continue
        ((line_number++))
        
        # Replace the line to be modified
        if [[ $line_number -eq $selection ]]; then
            echo "$new_name|$new_ip|$new_username|$new_password|$new_port|$new_group|$new_info" >> "$new_tmp_file"
        else
            # Write all other lines unchanged
            echo "$line" >> "$new_tmp_file"
        fi
    done < "$tmp_servers_file"

    # Replace the original temporary file
    mv "$new_tmp_file" "$tmp_servers_file"
    chmod 600 "$tmp_servers_file"

    # Success message
    # Use dynamic box width and centering
    local success_title="SUCCESS!"
    local success_emoji="✅"
    local success_visual_len=$((${#success_title} + 1 + 2))
    local success_box_width=$((success_visual_len + 8))
    [[ $success_box_width -lt $min_box_width ]] && success_box_width=$min_box_width
    [[ $success_box_width -gt $max_box_width ]] && success_box_width=$max_box_width
    local success_border=$(printf '═%.0s' $(seq 1 $success_box_width))
    local success_padding=$(( (success_box_width - success_visual_len) / 2 ))
    echo -e "\n${GREEN}╔${success_border}╗${NC}"
    printf "${GREEN}║%*s${CYAN}%s %s${GREEN}%*s║${NC}\n" \
        $success_padding "" \
        "$success_emoji" "$success_title" \
        $((success_box_width - success_visual_len - success_padding)) ""
    echo -e "${GREEN}╚${success_border}╝${NC}"
    echo -e "\n${GREEN}🎉 Server '$new_name' modified successfully!${NC}"
    echo -e "${CYAN}📊 Updated Details:${NC}"
    echo -e "   ${BLUE}Name:${NC} $new_name"
    echo -e "   ${BLUE}IP:${NC} $new_ip"
    echo -e "   ${BLUE}Username:${NC} $new_username"
    echo -e "   ${BLUE}Port:${NC} $new_port"
    [[ -n "$new_group" ]] && echo -e "   ${BLUE}Group:${NC} $new_group"
    [[ -n "$new_info" ]] && echo -e "   ${BLUE}Info:${NC} $new_info"
    echo -e "\n${YELLOW}💾 Backup saved as: $(basename "$backup_file")${NC}"

    # Log the modification
    log_event "SERVER_MODIFIED" "Server modified: $current_name → $new_name ($new_ip)" "$new_name|$new_ip"
    STATS[vault_operations]=$((${STATS[vault_operations]} + 1))

    echo -e "\n${YELLOW}💡 Tip: Use 'List Servers' to view all servers in the vault.${NC}"
    return 0
}