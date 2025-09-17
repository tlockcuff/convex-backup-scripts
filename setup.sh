#!/bin/bash

# Enable strict error handling
set -euo pipefail

# Configuration
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly ENV_FILE="$SCRIPT_DIR/.env"

# Colors for output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m' # No Color

# Logging functions
log_info() { echo -e "${BLUE}[INFO]${NC} $*"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $*"; }
log_error() { echo -e "${RED}[ERROR]${NC} $*"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $*"; }

# Help function
show_help() {
    cat << EOF
${BLUE}Convex Backup Setup Tool${NC}

This script helps you configure the Convex backup tool.

Usage: $0 [OPTIONS]

OPTIONS:
    --password PASSWORD     Set a specific backup password
    --generate-password     Generate a secure random password
    --convex-key KEY        Set Convex self-hosted admin key
    --convex-url URL        Set Convex self-hosted URL
    --retention DAYS        Set backup retention policy (default: 14)
    --cron EXPRESSION       Set cron schedule (default: "0 12 * * *")
    --check                 Check current configuration
    -h, --help              Show this help message

EXAMPLES:
    $0 --generate-password                    # Generate secure password
    $0 --password "my-secure-password"        # Set specific password
    $0 --convex-key "your-admin-key"          # Set Convex admin key
    $0 --check                                # Check configuration status

If run without arguments, enters interactive setup mode.
EOF
}

# Generate a secure password
generate_password() {
    openssl rand -base64 32 | tr -d "=+/" | cut -c1-32
}

# Validate password strength
validate_password() {
    local password="$1"
    local min_length=12
    
    if [[ ${#password} -lt $min_length ]]; then
        log_error "Password must be at least $min_length characters long"
        return 1
    fi
    
    # Check for at least one number, one letter
    if ! [[ "$password" =~ [0-9] ]] || ! [[ "$password" =~ [a-zA-Z] ]]; then
        log_warn "Password should contain both letters and numbers for better security"
    fi
    
    return 0
}

# Read current configuration
read_config() {
    if [[ -f "$ENV_FILE" ]]; then
        source "$ENV_FILE"
    fi
}

# Write configuration to .env file
write_config() {
    local backup_password="${BACKUP_PASSWORD:-}"
    local convex_key="${CONVEX_SELF_HOSTED_ADMIN_KEY:-}"
    local convex_url="${CONVEX_SELF_HOSTED_URL:-}"
    local retention="${RETENTION_POLICY:-14}"
    local aws_region="${AWS_REGION:-}"
    local aws_access_key="${AWS_ACCESS_KEY_ID:-}"
    local aws_secret_key="${AWS_SECRET_ACCESS_KEY:-}"
    local aws_bucket="${AWS_BUCKET_NAME:-}"
    
    {
        echo "# Convex Backup Configuration"
        echo "# Generated on $(date)"
        echo ""
        echo "# Backup encryption password (required)"
        echo "BACKUP_PASSWORD=\"$backup_password\""
        echo ""
        echo "# Convex self-hosted configuration (optional)"
        echo "CONVEX_SELF_HOSTED_ADMIN_KEY=\"$convex_key\""
        echo "CONVEX_SELF_HOSTED_URL=\"$convex_url\""
        echo ""
        echo "# AWS S3 configuration (optional - for cloud backup storage)"
        echo "AWS_REGION=\"$aws_region\""
        echo "AWS_ACCESS_KEY_ID=\"$aws_access_key\""
        echo "AWS_SECRET_ACCESS_KEY=\"$aws_secret_key\""
        echo "AWS_BUCKET_NAME=\"$aws_bucket\""
        echo ""
        echo "# Backup retention policy in days (optional, default: 14)"
        echo "RETENTION_POLICY=$retention"
    } > "$ENV_FILE"
    
    chmod 600 "$ENV_FILE"
    log_success "Configuration saved to $ENV_FILE"
}

# Check configuration status
check_config() {
    log_info "Checking configuration status..."
    
    if [[ ! -f "$ENV_FILE" ]]; then
        log_error ".env file not found"
        return 1
    fi
    
    read_config
    
    echo -e "\n${BLUE}Current Configuration:${NC}"
    printf "%-30s | %s\n" "Setting" "Status"
    printf -- "-------------------------------|------------------\n"
    
    # Check backup password
    if [[ -n "${BACKUP_PASSWORD:-}" ]]; then
        printf "%-30s | %s\n" "Backup Password" "${GREEN}✓ Set (${#BACKUP_PASSWORD} chars)${NC}"
    else
        printf "%-30s | %s\n" "Backup Password" "${RED}✗ Not set${NC}"
    fi
    
    # Check Convex admin key
    if [[ -n "${CONVEX_SELF_HOSTED_ADMIN_KEY:-}" ]]; then
        printf "%-30s | %s\n" "Convex Admin Key" "${GREEN}✓ Set${NC}"
    else
        printf "%-30s | %s\n" "Convex Admin Key" "${YELLOW}○ Not set${NC}"
    fi
    
    # Check Convex URL
    if [[ -n "${CONVEX_SELF_HOSTED_URL:-}" ]]; then
        printf "%-30s | %s\n" "Convex URL" "${GREEN}✓ Set${NC}"
    else
        printf "%-30s | %s\n" "Convex URL" "${YELLOW}○ Not set${NC}"
    fi
    
    # Check retention policy
    local retention="${RETENTION_POLICY:-14}"
    printf "%-30s | %s\n" "Retention Policy" "${GREEN}$retention days${NC}"
    
    # Check AWS S3 configuration
    if [[ -n "${AWS_BUCKET_NAME:-}" ]]; then
        printf "%-30s | %s\n" "AWS S3 Bucket" "${GREEN}${AWS_BUCKET_NAME}${NC}"
        if [[ -n "${AWS_REGION:-}" ]]; then
            printf "%-30s | %s\n" "AWS Region" "${GREEN}${AWS_REGION}${NC}"
        else
            printf "%-30s | %s\n" "AWS Region" "${RED}✗ Not set${NC}"
        fi
        if [[ -n "${AWS_ACCESS_KEY_ID:-}" ]]; then
            printf "%-30s | %s\n" "AWS Access Key" "${GREEN}✓ Set${NC}"
        else
            printf "%-30s | %s\n" "AWS Access Key" "${RED}✗ Not set${NC}"
        fi
        if [[ -n "${AWS_SECRET_ACCESS_KEY:-}" ]]; then
            printf "%-30s | %s\n" "AWS Secret Key" "${GREEN}✓ Set${NC}"
        else
            printf "%-30s | %s\n" "AWS Secret Key" "${RED}✗ Not set${NC}"
        fi
    else
        printf "%-30s | %s\n" "AWS S3 Upload" "${YELLOW}○ Disabled${NC}"
    fi
    
    # Check script permissions
    if [[ -x "$SCRIPT_DIR/backup.sh" ]]; then
        printf "%-30s | %s\n" "backup.sh executable" "${GREEN}✓ Yes${NC}"
    else
        printf "%-30s | %s\n" "backup.sh executable" "${RED}✗ No${NC}"
    fi
    
    if [[ -x "$SCRIPT_DIR/restore.sh" ]]; then
        printf "%-30s | %s\n" "restore.sh executable" "${GREEN}✓ Yes${NC}"
    else
        printf "%-30s | %s\n" "restore.sh executable" "${RED}✗ No${NC}"
    fi
    
    echo ""
    
    # Check dependencies
    log_info "Checking dependencies..."
    local deps_ok=true
    
    for cmd in openssl npx unzip; do
        if command -v "$cmd" &> /dev/null; then
            printf "%-30s | %s\n" "$cmd" "${GREEN}✓ Available${NC}"
        else
            printf "%-30s | %s\n" "$cmd" "${RED}✗ Missing${NC}"
            deps_ok=false
        fi
    done
    
    echo ""
    
    if [[ "$deps_ok" == "true" ]] && [[ -n "${BACKUP_PASSWORD:-}" ]]; then
        log_success "Configuration looks good! You can run ./backup.sh to create your first backup."
    else
        log_warn "Configuration needs attention. Please address the issues above."
    fi
}

# Interactive setup
interactive_setup() {
    echo -e "${BLUE}=== Convex Backup Interactive Setup ===${NC}\n"
    
    read_config
    
    # Backup password setup
    echo -e "${BLUE}1. Backup Password Setup${NC}"
    if [[ -n "${BACKUP_PASSWORD:-}" ]]; then
        echo "Current password is set (${#BACKUP_PASSWORD} characters)"
        read -p "Do you want to change it? [y/N]: " change_password
        change_password=${change_password:-n}
    else
        change_password="y"
    fi
    
    if [[ "$change_password" =~ ^[Yy] ]]; then
        echo "Choose password option:"
        echo "1) Generate secure password automatically"
        echo "2) Enter custom password"
        read -p "Select option [1]: " password_option
        password_option=${password_option:-1}
        
        case $password_option in
            1)
                BACKUP_PASSWORD=$(generate_password)
                log_success "Generated secure password: $BACKUP_PASSWORD"
                echo "Please save this password in a secure location!"
                ;;
            2)
                while true; do
                    read -sp "Enter backup password: " BACKUP_PASSWORD
                    echo ""
                    if validate_password "$BACKUP_PASSWORD"; then
                        read -sp "Confirm password: " confirm_password
                        echo ""
                        if [[ "$BACKUP_PASSWORD" == "$confirm_password" ]]; then
                            log_success "Password set successfully"
                            break
                        else
                            log_error "Passwords don't match"
                        fi
                    fi
                done
                ;;
            *)
                log_error "Invalid option"
                exit 1
                ;;
        esac
    fi
    
    # Convex configuration
    echo -e "\n${BLUE}2. Convex Configuration (Optional)${NC}"
    echo "For self-hosted Convex instances, you can set admin key and URL."
    
    read -p "Do you want to configure Convex settings? [y/N]: " configure_convex
    configure_convex=${configure_convex:-n}
    
    if [[ "$configure_convex" =~ ^[Yy] ]]; then
        read -p "Convex admin key [${CONVEX_SELF_HOSTED_ADMIN_KEY:-}]: " input_key
        CONVEX_SELF_HOSTED_ADMIN_KEY=${input_key:-${CONVEX_SELF_HOSTED_ADMIN_KEY:-}}
        
        read -p "Convex URL [${CONVEX_SELF_HOSTED_URL:-}]: " input_url
        CONVEX_SELF_HOSTED_URL=${input_url:-${CONVEX_SELF_HOSTED_URL:-}}
    fi
    
    # AWS S3 configuration
    echo -e "\n${BLUE}3. AWS S3 Configuration (Optional)${NC}"
    echo "Configure AWS S3 for cloud backup storage and automatic local cleanup."
    
    read -p "Do you want to configure AWS S3 backup? [y/N]: " configure_aws
    configure_aws=${configure_aws:-n}
    
    if [[ "$configure_aws" =~ ^[Yy] ]]; then
        read -p "AWS S3 Bucket Name [${AWS_BUCKET_NAME:-}]: " input_bucket
        AWS_BUCKET_NAME=${input_bucket:-${AWS_BUCKET_NAME:-}}
        
        read -p "AWS Region [${AWS_REGION:-us-east-1}]: " input_region
        AWS_REGION=${input_region:-${AWS_REGION:-us-east-1}}
        
        read -p "AWS Access Key ID [${AWS_ACCESS_KEY_ID:-}]: " input_access_key
        AWS_ACCESS_KEY_ID=${input_access_key:-${AWS_ACCESS_KEY_ID:-}}
        
        read -sp "AWS Secret Access Key: " input_secret_key
        echo ""
        if [[ -n "$input_secret_key" ]]; then
            AWS_SECRET_ACCESS_KEY="$input_secret_key"
        fi
        
        if [[ -n "$AWS_BUCKET_NAME" ]]; then
            echo "AWS S3 backup will be enabled. Local backups will be deleted after successful S3 upload."
        fi
    fi
    
    # Retention policy
    echo -e "\n${BLUE}4. Backup Retention Policy${NC}"
    local current_retention="${RETENTION_POLICY:-14}"
    read -p "Backup retention days [$current_retention]: " input_retention
    RETENTION_POLICY=${input_retention:-$current_retention}
    
    # Save configuration
    echo -e "\n${BLUE}5. Saving Configuration${NC}"
    write_config
    
    # Set script permissions
    echo -e "\n${BLUE}6. Setting Script Permissions${NC}"
    chmod +x "$SCRIPT_DIR/backup.sh" "$SCRIPT_DIR/status.sh" 2>/dev/null || true
    log_success "Script permissions set"
    
    echo -e "\n${GREEN}=== Setup Complete! ===${NC}"
    echo -e "You can now run:"
    echo -e "  ${BLUE}./backup.sh${NC}  - Create a backup"
    echo -e "  ${BLUE}./status.sh${NC}  - Check backup status"
    echo -e "  ${BLUE}./restore.sh${NC} - Restore a backup"
}

# Main function
main() {
    local password=""
    local generate_pass=false
    local convex_key=""
    local convex_url=""
    local retention=""
    local cron_expr=""
    local check_mode=false
    
    # Parse command line arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            --password)
                password="$2"
                shift 2
                ;;
            --generate-password)
                generate_pass=true
                shift
                ;;
            --convex-key)
                convex_key="$2"
                shift 2
                ;;
            --convex-url)
                convex_url="$2"
                shift 2
                ;;
            --retention)
                retention="$2"
                shift 2
                ;;
            --cron)
                cron_expr="$2"
                shift 2
                ;;
            --check)
                check_mode=true
                shift
                ;;
            -h|--help)
                show_help
                exit 0
                ;;
            *)
                log_error "Unknown option: $1"
                show_help
                exit 1
                ;;
        esac
    done
    
    # Handle check mode
    if [[ "$check_mode" == "true" ]]; then
        check_config
        exit 0
    fi
    
    # Handle non-interactive mode
    if [[ -n "$password" ]] || [[ "$generate_pass" == "true" ]] || [[ -n "$convex_key" ]] || [[ -n "$convex_url" ]] || [[ -n "$retention" ]]; then
        read_config
        
        if [[ "$generate_pass" == "true" ]]; then
            BACKUP_PASSWORD=$(generate_password)
            log_success "Generated password: $BACKUP_PASSWORD"
        elif [[ -n "$password" ]]; then
            if validate_password "$password"; then
                BACKUP_PASSWORD="$password"
                log_success "Password set"
            else
                exit 1
            fi
        fi
        
        if [[ -n "$convex_key" ]]; then
            CONVEX_SELF_HOSTED_ADMIN_KEY="$convex_key"
            log_success "Convex admin key set"
        fi
        
        if [[ -n "$convex_url" ]]; then
            CONVEX_SELF_HOSTED_URL="$convex_url"
            log_success "Convex URL set"
        fi
        
        if [[ -n "$retention" ]]; then
            RETENTION_POLICY="$retention"
            log_success "Retention policy set to $retention days"
        fi
        
        write_config
        chmod +x "$SCRIPT_DIR/backup.sh" "$SCRIPT_DIR/status.sh" 2>/dev/null || true
    else
        # Interactive mode
        interactive_setup
    fi
}

# Run main function
main "$@"
