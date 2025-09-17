#!/bin/bash

num_backups=$(ls -1 ./backups | wc -l)
size_backups=$(du -sh ./backups | awk '{print $1}')
oldest_backup=$(ls -1 ./backups | sort | head -n 1)
newest_backup=$(ls -1 ./backups | sort | tail -n 1)
crontab_line=$(crontab -l | grep -F "$PWD/backup.sh" || echo "Not found")

printf "\n%-25s | %s\n" "Status" "Value"
printf -- "---------------------------|-----------------------------\n"
printf "%-25s | %s\n" "Number of backups" "$num_backups"
printf "%-25s | %s\n" "Size of backups directory" "$size_backups"
printf "%-25s | %s\n" "Oldest backup" "$oldest_backup"
printf "%-25s | %s\n" "Newest backup" "$newest_backup"
printf "%-25s | %s\n" "Crontab line" "$crontab_line"