#!/bin/bash

# Enable strict error handling
set -euo pipefail

# Configuration
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly BACKUPS_DIR="$SCRIPT_DIR/backups"
readonly LOG_FILE="$SCRIPT_DIR/backup.log"
readonly LOCK_FILE="$SCRIPT_DIR/backup.lock"

# Colors for output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m' # No Color

# Helper functions
format_size() {
    local size=$1
    if [[ $size -ge 1073741824 ]]; then
        echo "$(($size / 1073741824))GB"
    elif [[ $size -ge 1048576 ]]; then
        echo "$(($size / 1048576))MB"
    elif [[ $size -ge 1024 ]]; then
        echo "$(($size / 1024))KB"
    else
        echo "${size}B"
    fi
}

format_time_ago() {
    local timestamp=$1
    local current=$(date +%s)
    local diff=$((current - timestamp))
    
    if [[ $diff -lt 60 ]]; then
        echo "${diff}s ago"
    elif [[ $diff -lt 3600 ]]; then
        echo "$((diff / 60))m ago"
    elif [[ $diff -lt 86400 ]]; then
        echo "$((diff / 3600))h ago"
    else
        echo "$((diff / 86400))d ago"
    fi
}

# Check if backup is currently running
check_backup_status() {
    if [[ -f "$LOCK_FILE" ]]; then
        local pid=$(cat "$LOCK_FILE" 2>/dev/null || echo "")
        if [[ -n "$pid" ]] && kill -0 "$pid" 2>/dev/null; then
            echo -e "${YELLOW}RUNNING${NC} (PID: $pid)"
        else
            echo -e "${RED}STALE LOCK${NC}"
        fi
    else
        echo -e "${GREEN}IDLE${NC}"
    fi
}

# Get backup statistics
get_backup_stats() {
    if [[ ! -d "$BACKUPS_DIR" ]]; then
        echo "0|0|N/A|N/A|N/A|N/A"
        return
    fi
    
    local count=0
    local total_size=0
    local oldest_file=""
    local newest_file=""
    local oldest_time=""
    local newest_time=""
    
    while IFS= read -r -d '' file; do
        ((count++))
        local size=$(stat -f%z "$file" 2>/dev/null || stat -c%s "$file" 2>/dev/null || echo 0)
        total_size=$((total_size + size))
        
        local mtime=$(stat -f%m "$file" 2>/dev/null || stat -c%Y "$file" 2>/dev/null || echo 0)
        
        if [[ -z "$oldest_time" ]] || [[ $mtime -lt $oldest_time ]]; then
            oldest_time=$mtime
            oldest_file=$(basename "$file")
        fi
        
        if [[ -z "$newest_time" ]] || [[ $mtime -gt $newest_time ]]; then
            newest_time=$mtime
            newest_file=$(basename "$file")
        fi
    done < <(find "$BACKUPS_DIR" -name "*.zip.enc" -type f -print0 2>/dev/null || true)
    
    echo "$count|$total_size|$oldest_file|$newest_file|$oldest_time|$newest_time"
}

# Check disk space
get_disk_info() {
    local available=$(df "$SCRIPT_DIR" | awk 'NR==2 {print $4}')
    local total=$(df "$SCRIPT_DIR" | awk 'NR==2 {print $2}')
    local used=$(df "$SCRIPT_DIR" | awk 'NR==2 {print $3}')
    local percent=$(df "$SCRIPT_DIR" | awk 'NR==2 {print $5}')
    
    echo "$(format_size $((available * 1024)))|$(format_size $((total * 1024)))|$(format_size $((used * 1024)))|$percent"
}

# Get last backup result from log
get_last_backup_result() {
    if [[ ! -f "$LOG_FILE" ]]; then
        echo "N/A|N/A"
        return
    fi
    
    local last_success=$(grep "Backup completed successfully" "$LOG_FILE" | tail -1 | cut -d']' -f1 | tr -d '[' || echo "")
    local last_error=$(grep "ERROR" "$LOG_FILE" | tail -1 | cut -d']' -f1 | tr -d '[' || echo "")
    
    echo "$last_success|$last_error"
}

# Get cron job info
get_cron_info() {
    local cron_line=$(crontab -l 2>/dev/null | grep -F "$SCRIPT_DIR/backup.sh" || echo "")
    if [[ -n "$cron_line" ]]; then
        local schedule=$(echo "$cron_line" | awk '{print $1" "$2" "$3" "$4" "$5}')
        echo -e "${GREEN}ENABLED${NC}|$schedule"
    else
        echo -e "${RED}NOT CONFIGURED${NC}|N/A"
    fi
}

# Test backup integrity (check if we can decrypt latest backup)
test_backup_integrity() {
    if [[ ! -f "$SCRIPT_DIR/.env" ]]; then
        echo -e "${RED}NO .env FILE${NC}"
        return
    fi
    
    source "$SCRIPT_DIR/.env"
    
    if [[ -z "${BACKUP_PASSWORD:-}" ]]; then
        echo -e "${RED}NO PASSWORD${NC}"
        return
    fi
    
    local latest_backup=$(find "$BACKUPS_DIR" -name "*.zip.enc" -type f -exec stat -f "%m %N" {} \; 2>/dev/null | sort -nr | head -1 | cut -d' ' -f2- || echo "")
    
    if [[ -z "$latest_backup" ]]; then
        echo -e "${YELLOW}NO BACKUPS${NC}"
        return
    fi
    
    # Simple decryption test - just check if we can start decrypting
    if openssl enc -aes-256-cbc -d -salt -pbkdf2 -iter 100000 -in "$latest_backup" -pass pass:"$BACKUP_PASSWORD" 2>/dev/null | head -c 1 >/dev/null 2>&1; then
        echo -e "${GREEN}DECRYPTABLE${NC}"
    elif openssl enc -aes-256-cbc -d -salt -in "$latest_backup" -pass pass:"$BACKUP_PASSWORD" 2>/dev/null | head -c 1 >/dev/null 2>&1; then
        echo -e "${GREEN}DECRYPTABLE${NC}"
    else
        echo -e "${RED}CANNOT DECRYPT${NC}"
    fi
}

# Main status display
main() {
    echo -e "\n${BLUE}=== Convex Backup Status ===${NC}\n"
    
    # Get all data
    local backup_status=$(check_backup_status)
    IFS='|' read -r count total_size oldest_file newest_file oldest_time newest_time <<< "$(get_backup_stats)"
    IFS='|' read -r disk_avail disk_total disk_used disk_percent <<< "$(get_disk_info)"
    IFS='|' read -r last_success last_error <<< "$(get_last_backup_result)"
    IFS='|' read -r cron_status cron_schedule <<< "$(get_cron_info)"
    local integrity_status=$(test_backup_integrity)
    
    # Display status table
    printf "%-30s | %s\n" "Property" "Value"
    printf -- "-------------------------------|----------------------------------------\n"
    printf "%-30s | %s\n" "Backup Process Status" "$backup_status"
    printf "%-30s | %s\n" "Number of Backups" "$count"
    printf "%-30s | %s\n" "Total Backup Size" "$(format_size $total_size)"
    
    if [[ "$count" -gt 0 ]]; then
        printf "%-30s | %s (%s)\n" "Oldest Backup" "$oldest_file" "$(format_time_ago $oldest_time)"
        printf "%-30s | %s (%s)\n" "Newest Backup" "$newest_file" "$(format_time_ago $newest_time)"
        printf "%-30s | %s\n" "Latest Backup Status" "$integrity_status"
    fi
    
    printf "%-30s | %s\n" "Disk Space Available" "$disk_avail"
    printf "%-30s | %s\n" "Disk Space Used" "$disk_used ($disk_percent)"
    printf "%-30s | %s\n" "Cron Job Status" "$cron_status"
    
    if [[ "$cron_schedule" != "N/A" ]]; then
        printf "%-30s | %s\n" "Backup Schedule" "$cron_schedule"
    fi
    
    if [[ -n "$last_success" ]]; then
        printf "%-30s | %s\n" "Last Successful Backup" "$last_success"
    fi
    
    if [[ -n "$last_error" ]]; then
        printf "%-30s | %s\n" "Last Error" "$last_error"
    fi
    
    # Warnings and recommendations
    echo -e "\n${BLUE}=== Health Checks ===${NC}"
    
    local warnings=0
    
    # Check if backups exist
    if [[ "$count" -eq 0 ]]; then
        echo -e "${YELLOW}⚠️  No backups found${NC}"
        ((warnings++))
    fi
    
    # Check if latest backup is too old
    if [[ -n "$newest_time" ]] && [[ $newest_time -lt $(($(date +%s) - 86400)) ]]; then
        echo -e "${YELLOW}⚠️  Latest backup is older than 24 hours${NC}"
        ((warnings++))
    fi
    
    # Check disk space
    local disk_percent_num=$(echo "$disk_percent" | tr -d '%')
    if [[ $disk_percent_num -gt 90 ]]; then
        echo -e "${RED}⚠️  Disk space is critically low ($disk_percent used)${NC}"
        ((warnings++))
    elif [[ $disk_percent_num -gt 80 ]]; then
        echo -e "${YELLOW}⚠️  Disk space is getting low ($disk_percent used)${NC}"
        ((warnings++))
    fi
    
    # Check cron job
    if [[ "$cron_status" == *"NOT CONFIGURED"* ]]; then
        echo -e "${YELLOW}⚠️  Cron job is not configured for automatic backups${NC}"
        ((warnings++))
    fi
    
    # Check integrity
    if [[ "$integrity_status" == *"CORRUPT"* ]]; then
        echo -e "${RED}⚠️  Latest backup appears to be corrupted${NC}"
        ((warnings++))
    elif [[ "$integrity_status" == *"NO PASSWORD"* ]]; then
        echo -e "${YELLOW}⚠️  Cannot verify backup integrity - password not configured${NC}"
        ((warnings++))
    fi
    
    if [[ $warnings -eq 0 ]]; then
        echo -e "${GREEN}✅ All checks passed${NC}"
    else
        echo -e "${YELLOW}Found $warnings warning(s) above${NC}"
    fi
    
    echo ""
}

# Run main function
main "$@"