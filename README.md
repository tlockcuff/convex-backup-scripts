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

## Prerequisites

- Node.js (v24.8.0 recommended, managed by Volta)
- Convex CLI access
- OpenSSL (typically pre-installed on macOS/Linux)
- A Convex project with appropriate permissions

## Setup

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

4. **Add self-hosted convex admin key and url to the .env file**
   ```bash
   CONVEX_SELF_HOSTED_ADMIN_KEY=""
   CONVEX_SELF_HOSTED_URL=""
   ``` 

5. **Make the backup script executable**:
   ```bash
   chmod +x backup.sh
   ```

## Usage

### Running a Backup

```bash
./backup.sh
```

The script will:
1. Create a `backups/` directory if it doesn't exist
2. Export your Convex database with file storage
3. Encrypt the backup using your password
4. Delete the unencrypted file
5. Save the encrypted backup as `YYYYMMDDHHMMSS.zip.enc`

### Environment Variables

Configure the tool using the `.env` file:

```env
BACKUP_PASSWORD=your-secure-password-here
```

### Example Output

```
Backup created and encrypted successfully
```

Your encrypted backup will be saved in the `backups/` directory with a filename like:
```
20240917143022.zip.enc
```

## Restoring Backups

To decrypt and restore a backup:

```bash
# Decrypt the backup
openssl enc -aes-256-cbc -d -salt -in ./backups/20240917143022.zip.enc -out restored-backup.zip -pass pass:your-password

# Extract the backup
unzip restored-backup.zip

# Import back to Convex (refer to Convex documentation for import commands)
```

## Security Notes

- 🔐 The `.env` file contains your encryption password and is excluded from version control
- 🗂️ The `backups/` directory is also gitignored to prevent accidental commits
- 🔒 Original unencrypted backup files are automatically deleted
- 💾 Keep your encryption password safe - you'll need it to restore backups