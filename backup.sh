#!/bin/bash

# Load environment variables
source .env

# Check if backup password is set
if [ -z "$BACKUP_PASSWORD" ]; then
    echo "Error: BACKUP_PASSWORD not set in .env file"
    exit 1
fi

# create the backups directory if it doesn't exist
mkdir -p backups

# define a timestamp for the backup file
timestamp=$(date +%Y%m%d%H%M%S)

# export the convex database
npx --yes convex export --include-file-storage --path ./backups/$timestamp.zip

# encrypt the backup file
openssl enc -aes-256-cbc -salt -in ./backups/$timestamp.zip -out ./backups/$timestamp.zip.enc -pass pass:$BACKUP_PASSWORD

# delete the original backup file
rm ./backups/$timestamp.zip

# print a success message
echo "Backup created and encrypted successfully"