#!/bin/bash

# Enable strict error handling
set -euo pipefail

# Configuration variables
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly TIMESTAMP=$(date +%Y%m%d%H%M%S)
readonly BACKUP_SCRIPT="$SCRIPT_DIR/backup.sh"
readonly CRON_EXPRESSION="0 23 * * *" # every day at 11:00 PM
readonly RETENTION_POLICY=${RETENTION_POLICY:-14} # 14 days default
readonly BACKUPS_DIR="$SCRIPT_DIR/backups"
readonly LOG_FILE="$SCRIPT_DIR/backup.log"
readonly LOCK_FILE="$SCRIPT_DIR/backup.lock"

# Colors for output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
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

# Error handling function
cleanup_on_error() {
    local exit_code=$?
    log_error "Script failed with exit code $exit_code"
    
    # Remove incomplete backup files
    if [[ -f "$BACKUPS_DIR/$TIMESTAMP.zip" ]]; then
        log_info "Removing incomplete backup file"
        rm -f "$BACKUPS_DIR/$TIMESTAMP.zip"
    fi
    
    # Remove lock file
    [[ -f "$LOCK_FILE" ]] && rm -f "$LOCK_FILE"
    
    exit $exit_code
}

# Set up error handling
trap cleanup_on_error ERR EXIT

# Check if script is already running
check_lock() {
    if [[ -f "$LOCK_FILE" ]]; then
        local pid=$(cat "$LOCK_FILE" 2>/dev/null || echo "")
        if [[ -n "$pid" ]] && kill -0 "$pid" 2>/dev/null; then
            log_error "Backup script is already running (PID: $pid)"
            exit 1
        else
            log_warn "Stale lock file found, removing it"
            rm -f "$LOCK_FILE"
        fi
    fi
    
    # Create lock file
    echo $$ > "$LOCK_FILE"
    log_info "Created lock file with PID $$"
}

# Validate environment and configuration
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
    
    if [[ ${#BACKUP_PASSWORD} -lt 12 ]]; then
        log_error "BACKUP_PASSWORD is too short (minimum 12 characters required)"
        exit 1
    fi
    
    # Check required commands
    local required_commands=("npx" "openssl" "find" "crontab")
    for cmd in "${required_commands[@]}"; do
        if ! command -v "$cmd" &> /dev/null; then
            log_error "Required command '$cmd' is not installed"
            exit 1
        fi
    done
    
    # Check AWS configuration if S3 upload is enabled
    if [[ -n "${AWS_BUCKET_NAME:-}" ]]; then
        log_info "AWS S3 upload enabled - validating AWS configuration..."
        
        if [[ -z "${AWS_REGION:-}" ]]; then
            log_error "AWS_REGION is required when AWS_BUCKET_NAME is set"
            exit 1
        fi
        
        if [[ -z "${AWS_ACCESS_KEY_ID:-}" ]]; then
            log_error "AWS_ACCESS_KEY_ID is required when AWS_BUCKET_NAME is set"
            exit 1
        fi
        
        if [[ -z "${AWS_SECRET_ACCESS_KEY:-}" ]]; then
            log_error "AWS_SECRET_ACCESS_KEY is required when AWS_BUCKET_NAME is set"
            exit 1
        fi
        
        # Check if AWS CLI is available
        if ! command -v "aws" &> /dev/null; then
            log_error "AWS CLI is required for S3 upload but not found"
            log_error "Please install AWS CLI: https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html"
            exit 1
        fi
        
        log_success "AWS S3 configuration validated"
    else
        log_info "AWS S3 upload disabled - backups will be stored locally only"
    fi
    
    
    # Check available disk space (require at least 1GB free)
    local available_space=$(df "$SCRIPT_DIR" | awk 'NR==2 {print $4}')
    local required_space=1048576 # 1GB in KB
    
    if [[ "$available_space" -lt "$required_space" ]]; then
        log_error "Insufficient disk space. Available: $(($available_space/1024))MB, Required: $(($required_space/1024))MB"
        exit 1
    fi
    
    log_success "Configuration validation passed"
}

# Check if Convex is accessible
check_convex_access() {
    log_info "Checking Convex access..."
    
    if ! npx --yes convex --version &> /dev/null; then
        log_error "Convex CLI is not accessible"
        exit 1
    fi
    
    log_success "Convex CLI is accessible"
}

# Create backup function
create_backup() {
    log_info "Starting backup creation..."
    
    # Create the backups directory with proper permissions
    mkdir -p "$BACKUPS_DIR"
    chmod 700 "$BACKUPS_DIR"
    
    local backup_file="$BACKUPS_DIR/$TIMESTAMP.zip"
    local encrypted_file="$backup_file.enc"
    
    # Export the convex database
    log_info "Exporting Convex database..."
    if ! npx --yes convex export --include-file-storage --path "$backup_file"; then
        log_error "Failed to export Convex database"
        exit 1
    fi
    
    # Verify backup file was created and has content
    if [[ ! -f "$backup_file" ]]; then
        log_error "Backup file was not created: $backup_file"
        exit 1
    fi
    
    local backup_size=$(stat -f%z "$backup_file" 2>/dev/null || stat -c%s "$backup_file" 2>/dev/null)
    if [[ "$backup_size" -eq 0 ]]; then
        log_error "Backup file is empty: $backup_file"
        exit 1
    fi
    
    log_success "Database exported successfully ($(($backup_size/1024/1024))MB)"
    
    # Encrypt the backup file
    log_info "Encrypting backup file..."
    if ! openssl enc -aes-256-cbc -salt -pbkdf2 -iter 100000 -in "$backup_file" -out "$encrypted_file" -pass pass:"$BACKUP_PASSWORD"; then
        log_error "Failed to encrypt backup file"
        exit 1
    fi
    
    # Verify encrypted file was created
    if [[ ! -f "$encrypted_file" ]]; then
        log_error "Encrypted backup file was not created: $encrypted_file"
        exit 1
    fi
    
    # Set secure permissions on encrypted file
    chmod 600 "$encrypted_file"
    
    log_success "Backup file encrypted successfully"
    
    # Delete the original backup file
    log_info "Removing unencrypted backup file..."
    rm "$backup_file"
    log_success "Unencrypted backup file removed"
    
    log_success "Backup created and encrypted"
    
    # Upload to S3 if configured
    upload_to_s3 "$encrypted_file"
    
    return 0
}

# Upload backup to S3 and clean up local file
upload_to_s3() {
    local encrypted_file="$1"
    local filename=$(basename "$encrypted_file")
    
    if [[ -z "${AWS_BUCKET_NAME:-}" ]]; then
        log_info "S3 upload disabled - keeping backup locally"
        return 0
    fi
    
    log_info "Uploading backup to S3..."
    
    # Set AWS environment variables for this session
    export AWS_REGION="${AWS_REGION}"
    export AWS_ACCESS_KEY_ID="${AWS_ACCESS_KEY_ID}"
    export AWS_SECRET_ACCESS_KEY="${AWS_SECRET_ACCESS_KEY}"
    
    # Create S3 key with date prefix for organization
    local s3_key="convex-backups/$(date +%Y)/$(date +%m)/$(date +%d)/$filename"
    
    # Upload to S3
    if aws s3 cp "$encrypted_file" "s3://${AWS_BUCKET_NAME}/$s3_key" --storage-class STANDARD_IA; then
        log_success "Backup uploaded to S3: s3://${AWS_BUCKET_NAME}/$s3_key"
        
        # Verify the upload by checking if file exists in S3
        if aws s3 ls "s3://${AWS_BUCKET_NAME}/$s3_key" >/dev/null 2>&1; then
            log_info "Upload verified - removing local backup to free space"
            rm "$encrypted_file"
            log_success "Local backup file removed: $filename"
        else
            log_error "S3 upload verification failed - keeping local backup"
            return 1
        fi
    else
        log_error "Failed to upload backup to S3 - keeping local backup"
        return 1
    fi
    
    return 0
}

# Apply retention policy
apply_retention_policy() {
    log_info "Applying retention policy (${RETENTION_POLICY} days)..."
    
    # Clean up local backups
    local deleted_count=0
    while IFS= read -r -d '' file; do
        log_info "Removing old local backup: $(basename "$file")"
        rm "$file"
        ((deleted_count++))
    done < <(find "$BACKUPS_DIR" -name "*.zip.enc" -type f -mtime "+$RETENTION_POLICY" -print0 2>/dev/null || true)
    
    if [[ $deleted_count -gt 0 ]]; then
        log_success "Removed $deleted_count old local backup(s)"
    else
        log_info "No old local backups to remove"
    fi
    
    # Clean up S3 backups if S3 is configured
    if [[ -n "${AWS_BUCKET_NAME:-}" ]]; then
        log_info "Cleaning up old S3 backups..."
        cleanup_s3_backups
    fi
}

# Clean up old S3 backups
cleanup_s3_backups() {
    # Set AWS environment variables
    export AWS_REGION="${AWS_REGION}"
    export AWS_ACCESS_KEY_ID="${AWS_ACCESS_KEY_ID}"
    export AWS_SECRET_ACCESS_KEY="${AWS_SECRET_ACCESS_KEY}"
    
    # Calculate cutoff date
    local cutoff_date
    if command -v "gdate" &> /dev/null; then
        # macOS with GNU date installed
        cutoff_date=$(gdate -d "-${RETENTION_POLICY} days" +%Y-%m-%d)
    elif date --version >/dev/null 2>&1; then
        # Linux with GNU date
        cutoff_date=$(date -d "-${RETENTION_POLICY} days" +%Y-%m-%d)
    else
        # macOS with BSD date
        cutoff_date=$(date -v-${RETENTION_POLICY}d +%Y-%m-%d)
    fi
    
    log_info "Removing S3 backups older than $cutoff_date..."
    
    # List and delete old S3 objects
    local deleted_s3_count=0
    while IFS= read -r s3_object; do
        if [[ -n "$s3_object" ]]; then
            # Extract date from S3 key (format: convex-backups/YYYY/MM/DD/filename)
            local object_date=$(echo "$s3_object" | grep -o 'convex-backups/[0-9]\{4\}/[0-9]\{2\}/[0-9]\{2\}/' | sed 's|convex-backups/||; s|/|-|g; s|-$||')
            
            if [[ "$object_date" < "$cutoff_date" ]]; then
                log_info "Removing old S3 backup: $s3_object"
                if aws s3 rm "s3://${AWS_BUCKET_NAME}/$s3_object" >/dev/null 2>&1; then
                    ((deleted_s3_count++))
                else
                    log_warn "Failed to remove S3 object: $s3_object"
                fi
            fi
        fi
    done < <(aws s3 ls "s3://${AWS_BUCKET_NAME}/convex-backups/" --recursive | grep '\.zip\.enc$' | awk '{print $4}' 2>/dev/null || true)
    
    if [[ $deleted_s3_count -gt 0 ]]; then
        log_success "Removed $deleted_s3_count old S3 backup(s)"
    else
        log_info "No old S3 backups to remove"
    fi
}

# Setup cron job
setup_cron() {
    log_info "Checking cron job setup..."
    
    # Check if any cron job exists for this backup script (regardless of log redirection)
    if crontab -l 2>/dev/null | grep -F "$BACKUP_SCRIPT" | grep -q "$CRON_EXPRESSION"; then
        log_info "Cron job already exists"
    else
        # Remove any existing entries for this script to avoid duplicates
        local temp_cron=$(mktemp)
        crontab -l 2>/dev/null | grep -v -F "$BACKUP_SCRIPT" > "$temp_cron" || true
        
        # Add the new cron job
        echo "$CRON_EXPRESSION $BACKUP_SCRIPT >> $LOG_FILE 2>&1" >> "$temp_cron"
        
        # Install the new crontab
        crontab "$temp_cron"
        rm -f "$temp_cron"
        
        log_success "Cron job added: $CRON_EXPRESSION"
    fi
}

# Main execution
main() {
    log_info "=== Convex Backup Script Started ==="
    
    # Initialize
    check_lock
    validate_config
    check_convex_access
    
    # Perform backup
    create_backup
    apply_retention_policy
    setup_cron
    
    # Success
    log_success "🎉 Backup completed successfully!"
    log_info "Encrypted backup saved as: $BACKUPS_DIR/$TIMESTAMP.zip.enc"
    
    # Clean up
    rm -f "$LOCK_FILE"
    
    # Reset trap to avoid cleanup on successful exit
    trap - ERR EXIT
}

# Run main function
main "$@"
