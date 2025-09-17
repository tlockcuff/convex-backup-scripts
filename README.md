# Convex Database Backup Tool

A secure, automated backup solution for Convex databases with built-in encryption.

## Overview

This tool creates encrypted backups of your Convex database, including file storage, using a simple shell script. All backups are automatically encrypted with AES-256-CBC encryption for security.

## Features

- 🔒 **Encrypted Backups**: AES-256-CBC encryption with OpenSSL
- 📁 **File Storage Included**: Backs up both database and file storage
- 🕐 **Timestamped**: Automatic timestamp-based file naming
- 🔐 **Secure**: Original unencrypted files are automatically deleted
- ⚙️ **Configurable**: Environment variable-based configuration
- 📊 **Comprehensive Status**: Real-time backup monitoring and health checks
- 🔄 **Automated Restore**: Interactive and command-line restore options
- 🛡️ **Error Handling**: Robust error handling with detailed logging
- 🔍 **Integrity Verification**: Automatic backup integrity checking
- 🚫 **Concurrency Protection**: Prevents multiple backup processes
- 📝 **Detailed Logging**: Structured logging with timestamps and colors
- 🎯 **Interactive Setup**: Easy configuration with guided setup

## Prerequisites

- Node.js (v24.8.0 recommended, managed by Volta)
- Convex CLI access
- OpenSSL (typically pre-installed on macOS/Linux)
- A Convex project with appropriate permissions

## Quick Setup

### Option 1: Interactive Setup (Recommended)
```bash
# Clone the repository
git clone <your-repo-url>
cd convex-backup

# Install dependencies
npm install

# Run interactive setup
./setup.sh
```

### Option 2: Manual Setup
1. **Clone/Download** this repository

2. **Install dependencies**:
   ```bash
   npm install
   ```

3. **Generate a backup password and create the .env file**:
   ```bash
   # Generate a secure password
   openssl rand -base64 32
   
   # Create .env file with the generated password
   echo "BACKUP_PASSWORD=your-generated-password-here" > .env
   ```

4. **Add self-hosted convex admin key and url to the .env file** (optional):
   ```bash
   echo "CONVEX_SELF_HOSTED_ADMIN_KEY=your-admin-key" >> .env
   echo "CONVEX_SELF_HOSTED_URL=your-convex-url" >> .env
   ``` 

5. **Make scripts executable**:
   ```bash
   chmod +x backup.sh status.sh restore.sh setup.sh
   ```

### Option 3: Command Line Setup
```bash
# Generate password automatically
./setup.sh --generate-password

# Or set specific password
./setup.sh --password "your-secure-password"

# Set Convex configuration
./setup.sh --convex-key "your-admin-key" --convex-url "your-url"

# Check configuration
./setup.sh --check
```

## Usage

### Creating Backups

```bash
# Create a backup
./backup.sh
```

The backup script will:
1. Validate configuration and check prerequisites
2. Create a `backups/` directory with secure permissions
3. Export your Convex database with file storage
4. Encrypt the backup using AES-256-CBC encryption
5. Verify backup integrity
6. Apply retention policy (remove old backups)
7. Set up cron job for automatic backups
8. Log all operations to `backup.log`

### Checking Status

```bash
# Check comprehensive backup status
./status.sh
```

The status script shows:
- Current backup process status
- Number and size of backups
- Oldest and newest backup information
- Disk space usage
- Cron job configuration
- Last backup success/error
- Health checks and warnings

### Restoring Backups

```bash
# List available backups
./restore.sh --list

# Interactive restore
./restore.sh --interactive

# Restore specific backup
./restore.sh 20240917143022.zip.enc

# Restore to custom directory
./restore.sh --output /path/to/restore 20240917143022.zip.enc

# Verify backup integrity only
./restore.sh --verify 20240917143022.zip.enc

# Test restore without extracting files
./restore.sh --test 20240917143022.zip.enc
```

### Configuration Management

```bash
# Check current configuration
./setup.sh --check

# Interactive configuration
./setup.sh

# Generate new password
./setup.sh --generate-password

# Set specific configuration
./setup.sh --password "new-password" --retention 30
```

### Environment Variables

Configure the tool using the `.env` file:

```env
# Required: Backup encryption password
BACKUP_PASSWORD=your-secure-password-here

# Optional: Self-hosted Convex configuration
CONVEX_SELF_HOSTED_ADMIN_KEY=your-admin-key
CONVEX_SELF_HOSTED_URL=your-convex-url

# Optional: Backup retention policy (days)
RETENTION_POLICY=14
```

### Example Output

```
[2024-09-17 14:30:22] [INFO] === Convex Backup Script Started ===
[2024-09-17 14:30:22] [INFO] Validating configuration...
[2024-09-17 14:30:22] [SUCCESS] Configuration validation passed
[2024-09-17 14:30:22] [INFO] Checking Convex access...
[2024-09-17 14:30:23] [SUCCESS] Convex CLI is accessible
[2024-09-17 14:30:23] [INFO] Starting backup creation...
[2024-09-17 14:30:23] [INFO] Exporting Convex database...
[2024-09-17 14:30:45] [SUCCESS] Database exported successfully (15MB)
[2024-09-17 14:30:45] [INFO] Encrypting backup file...
[2024-09-17 14:30:46] [SUCCESS] Backup file encrypted successfully
[2024-09-17 14:30:46] [INFO] Verifying backup integrity...
[2024-09-17 14:30:46] [SUCCESS] Backup integrity verified
[2024-09-17 14:30:46] [SUCCESS] 🎉 Backup completed successfully!
```

## Manual Restore (Alternative Method)

If you prefer to manually decrypt and restore a backup:

```bash
# Decrypt the backup
openssl enc -aes-256-cbc -d -salt -pbkdf2 -iter 100000 -in ./backups/20240917143022.zip.enc -out restored-backup.zip -pass pass:your-password

# Extract the backup
unzip restored-backup.zip

# Import back to Convex (refer to Convex documentation for import commands)
```

**Note**: The `./restore.sh` script provides a safer and more user-friendly way to restore backups.

## Security Notes

- 🔐 The `.env` file contains your encryption password and is excluded from version control
- 🗂️ The `backups/` directory is also gitignored to prevent accidental commits
- 🔒 Original unencrypted backup files are automatically deleted
- 💾 Keep your encryption password safe - you'll need it to restore backups
- 🛡️ Backup files have restrictive permissions (600) for security
- 🔍 Automatic integrity verification ensures backup files are not corrupted
- 🚫 Lock files prevent concurrent backup operations
- 📝 Detailed logging helps track all backup operations