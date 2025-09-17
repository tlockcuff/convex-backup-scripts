#!/bin/bash

# config variables
timestamp=$(date +%Y%m%d%H%M%S)
backup_script="$PWD/backup.sh"
cron_expression="0 12 * * *" # every day at 12:00 AM
retention_policy=14 # 14 days

# Load environment variables
source .env

# create the backups directory if it doesn't exist
mkdir -p backups

# export the convex database
npx --yes convex export --include-file-storage --path ./backups/$timestamp.zip

# encrypt the backup file
openssl enc -aes-256-cbc -salt -in ./backups/$timestamp.zip -out ./backups/$timestamp.zip.enc -pass pass:$BACKUP_PASSWORD

# delete the original backup file
rm ./backups/$timestamp.zip

# print a success message
echo "Backup created and encrypted successfully"

# apply a retention policy to the backups directory every time this script runs
find ./backups -type f -mtime +$retention_policy -exec rm {} \; 

# conditionally update crontab to run the backup script
if ! crontab -l | grep -q "$cron_expression $backup_script"; then
    (crontab -l 2>/dev/null; echo "$cron_expression $backup_script") | crontab -
fi