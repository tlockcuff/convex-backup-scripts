#!/bin/bash

# Enable strict error handling
set -euo pipefail

# Configuration
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly BACKUPS_DIR="$SCRIPT_DIR/backups"
readonly RESTORE_DIR="$SCRIPT_DIR/restore"
readonly LOG_FILE="$SCRIPT_DIR/restore.log"

# Colors for output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m' # No Color

# Logging function
log() {
    local level="$1"
    shift
    local message="$*"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo -e "[$timestamp] [$level] $message" | tee -a "$LOG_FILE"
}

log_info() { log "INFO" "$@"; }
log_warn() { log "WARN" "${YELLOW}$*${NC}"; }
log_error() { log "ERROR" "${RED}$*${NC}"; }
log_success() { log "SUCCESS" "${GREEN}$*${NC}"; }

# Help function
show_help() {
    cat << EOF
${BLUE}Convex Backup Restore Tool${NC}

Usage: $0 [OPTIONS] [BACKUP_FILE]

OPTIONS:
    -l, --list              List available backups
    -i, --interactive       Interactive backup selection
    -o, --output DIR        Specify output directory (default: ./restore)
    -t, --test              Test restore without extracting files
    -v, --verify            Verify backup integrity only
    -h, --help              Show this help message

EXAMPLES:
    $0 --list                           # List all available backups
    $0 --interactive                    # Interactive restore
    $0 20240917143022.zip.enc          # Restore specific backup
    $0 --verify 20240917143022.zip.enc # Verify backup integrity
    $0 --test --output /tmp/test       # Test restore to custom directory

If no backup file is specified, the most recent backup will be used.
EOF
}

# List available backups
list_backups() {
    log_info "Available backups:"
    
    if [[ ! -d "$BACKUPS_DIR" ]] || [[ -z "$(ls -A "$BACKUPS_DIR"/*.zip.enc 2>/dev/null || true)" ]]; then
        log_warn "No backup files found in $BACKUPS_DIR"
        exit 1
    fi
    
    echo -e "\n${BLUE}Available Backups:${NC}"
    printf "%-25s | %-10s | %-15s\n" "Filename" "Size" "Date"
    printf -- "--------------------------|------------|----------------\n"
    
    find "$BACKUPS_DIR" -name "*.zip.enc" -type f -exec stat -f "%m %z %N" {} \; 2>/dev/null | \
    sort -nr | \
    while read -r mtime size filepath; do
        local filename=$(basename "$filepath")
        local date_str=$(date -r "$mtime" "+%Y-%m-%d %H:%M" 2>/dev/null || echo "Unknown")
        local size_mb=$(( size / 1024 / 1024 ))
        printf "%-25s | %-10s | %s\n" "$filename" "${size_mb}MB" "$date_str"
    done
    
    echo ""
}

# Interactive backup selection
interactive_selection() {
    if [[ ! -d "$BACKUPS_DIR" ]] || [[ -z "$(ls -A "$BACKUPS_DIR"/*.zip.enc 2>/dev/null || true)" ]]; then
        log_error "No backup files found in $BACKUPS_DIR"
        exit 1
    fi
    
    echo -e "\n${BLUE}Select a backup to restore:${NC}\n"
    
    local -a backups=()
    local index=1
    
    find "$BACKUPS_DIR" -name "*.zip.enc" -type f -exec stat -f "%m %z %N" {} \; 2>/dev/null | \
    sort -nr | \
    while read -r mtime size filepath; do
        local filename=$(basename "$filepath")
        local date_str=$(date -r "$mtime" "+%Y-%m-%d %H:%M" 2>/dev/null || echo "Unknown")
        local size_mb=$(( size / 1024 / 1024 ))
        
        backups+=("$filepath")
        printf "%2d) %-25s (%sMB, %s)\n" "$index" "$filename" "$size_mb" "$date_str"
        ((index++))
    done
    
    echo ""
    read -p "Enter backup number [1]: " selection
    selection=${selection:-1}
    
    if ! [[ "$selection" =~ ^[0-9]+$ ]] || [[ "$selection" -lt 1 ]] || [[ "$selection" -gt ${#backups[@]} ]]; then
        log_error "Invalid selection: $selection"
        exit 1
    fi
    
    echo "${backups[$((selection-1))]}"
}

# Validate configuration
validate_config() {
    log_info "Validating configuration..."
    
    # Check if .env file exists
    if [[ ! -f "$SCRIPT_DIR/.env" ]]; then
        log_error ".env file not found. Please create it with BACKUP_PASSWORD variable."
        exit 1
    fi
    
    # Load environment variables
    source "$SCRIPT_DIR/.env"
    
    # Validate backup password
    if [[ -z "${BACKUP_PASSWORD:-}" ]]; then
        log_error "BACKUP_PASSWORD is not set in .env file"
        exit 1
    fi
    
    # Check required commands
    local required_commands=("openssl" "unzip")
    for cmd in "${required_commands[@]}"; do
        if ! command -v "$cmd" &> /dev/null; then
            log_error "Required command '$cmd' is not installed"
            exit 1
        fi
    done
    
    log_success "Configuration validation passed"
}

# Verify backup integrity
verify_backup() {
    local backup_file="$1"
    local backup_name=$(basename "$backup_file")
    
    log_info "Verifying backup integrity: $backup_name"
    
    if [[ ! -f "$backup_file" ]]; then
        log_error "Backup file not found: $backup_file"
        exit 1
    fi
    
    # Test decryption by decrypting to a temporary file
    local temp_test=$(mktemp)
    trap "rm -f '$temp_test'" EXIT
    
    # Try new method first, then fall back to legacy
    if ! openssl enc -aes-256-cbc -d -salt -pbkdf2 -iter 100000 -in "$backup_file" -out "$temp_test" -pass pass:"$BACKUP_PASSWORD" 2>/dev/null; then
        log_warn "New decryption method failed, trying legacy method..."
        if ! openssl enc -aes-256-cbc -d -salt -in "$backup_file" -out "$temp_test" -pass pass:"$BACKUP_PASSWORD" 2>/dev/null; then
            log_error "Failed to decrypt backup file with either method. Check your password."
            rm -f "$temp_test"
            exit 1
        fi
        log_info "Successfully decrypted with legacy method"
    fi
    
    # Test if it's a valid zip file
    if ! unzip -t "$temp_test" >/dev/null 2>&1; then
        log_error "Backup file appears to be corrupted (not a valid zip file)"
        rm -f "$temp_test"
        exit 1
    fi
    
    rm -f "$temp_test"
    
    log_success "Backup integrity verified successfully"
}

# Restore backup
restore_backup() {
    local backup_file="$1"
    local output_dir="$2"
    local test_only="${3:-false}"
    
    local backup_name=$(basename "$backup_file")
    log_info "Starting restore of: $backup_name"
    
    # Verify backup first
    verify_backup "$backup_file"
    
    if [[ "$test_only" == "true" ]]; then
        log_success "Test restore completed successfully (no files extracted)"
        return 0
    fi
    
    # Create output directory
    mkdir -p "$output_dir"
    
    # Create a temporary file for the decrypted backup
    local temp_backup=$(mktemp)
    trap "rm -f '$temp_backup'" EXIT
    
    # Decrypt the backup
    log_info "Decrypting backup file..."
    # Try new method first, then fall back to legacy
    if ! openssl enc -aes-256-cbc -d -salt -pbkdf2 -iter 100000 -in "$backup_file" -out "$temp_backup" -pass pass:"$BACKUP_PASSWORD" 2>/dev/null; then
        log_warn "New decryption method failed, trying legacy method..."
        if ! openssl enc -aes-256-cbc -d -salt -in "$backup_file" -out "$temp_backup" -pass pass:"$BACKUP_PASSWORD"; then
            log_error "Failed to decrypt backup file with either method"
            exit 1
        fi
        log_info "Successfully decrypted with legacy method"
    fi
    
    log_success "Backup decrypted successfully"
    
    # Extract the backup
    log_info "Extracting backup to: $output_dir"
    if ! unzip -q "$temp_backup" -d "$output_dir"; then
        log_error "Failed to extract backup file"
        exit 1
    fi
    
    log_success "Backup extracted successfully"
    
    # List extracted contents
    log_info "Extracted contents:"
    find "$output_dir" -type f | head -10 | while read -r file; do
        local relative_path=${file#$output_dir/}
        log_info "  $relative_path"
    done
    
    local total_files=$(find "$output_dir" -type f | wc -l)
    if [[ $total_files -gt 10 ]]; then
        log_info "  ... and $((total_files - 10)) more files"
    fi
    
    # Show restore instructions
    echo -e "\n${GREEN}=== Restore Complete ===${NC}"
    echo -e "Backup has been restored to: ${BLUE}$output_dir${NC}"
    echo -e "\nTo import the data back to Convex, you may need to:"
    echo -e "1. Review the extracted files"
    echo -e "2. Use Convex CLI import commands (refer to Convex documentation)"
    echo -e "3. Ensure your Convex project is properly configured"
    echo -e "\n${YELLOW}Note: This tool only extracts the backup. Import to Convex requires additional steps.${NC}"
}

# Get the most recent backup
get_latest_backup() {
    find "$BACKUPS_DIR" -name "*.zip.enc" -type f -exec stat -f "%m %N" {} \; 2>/dev/null | \
    sort -nr | \
    head -1 | \
    cut -d' ' -f2-
}

# Main function
main() {
    local list_mode=false
    local interactive_mode=false
    local output_dir="$RESTORE_DIR"
    local test_mode=false
    local verify_mode=false
    local backup_file=""
    
    # Parse command line arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            -l|--list)
                list_mode=true
                shift
                ;;
            -i|--interactive)
                interactive_mode=true
                shift
                ;;
            -o|--output)
                output_dir="$2"
                shift 2
                ;;
            -t|--test)
                test_mode=true
                shift
                ;;
            -v|--verify)
                verify_mode=true
                shift
                ;;
            -h|--help)
                show_help
                exit 0
                ;;
            -*)
                log_error "Unknown option: $1"
                show_help
                exit 1
                ;;
            *)
                backup_file="$1"
                shift
                ;;
        esac
    done
    
    log_info "=== Convex Backup Restore Tool Started ==="
    
    # Handle list mode
    if [[ "$list_mode" == "true" ]]; then
        list_backups
        exit 0
    fi
    
    # Validate configuration
    validate_config
    
    # Determine backup file to use
    if [[ "$interactive_mode" == "true" ]]; then
        backup_file=$(interactive_selection)
    elif [[ -z "$backup_file" ]]; then
        backup_file=$(get_latest_backup)
        if [[ -z "$backup_file" ]]; then
            log_error "No backup files found and no specific file provided"
            exit 1
        fi
        log_info "Using most recent backup: $(basename "$backup_file")"
    else
        # If backup_file doesn't contain a path, assume it's in the backups directory
        if [[ "$backup_file" != /* ]] && [[ "$backup_file" != ./* ]]; then
            backup_file="$BACKUPS_DIR/$backup_file"
        fi
    fi
    
    # Handle verify mode
    if [[ "$verify_mode" == "true" ]]; then
        verify_backup "$backup_file"
        exit 0
    fi
    
    # Perform restore
    restore_backup "$backup_file" "$output_dir" "$test_mode"
    
    log_success "Restore operation completed successfully!"
}

# Run main function
main "$@"
