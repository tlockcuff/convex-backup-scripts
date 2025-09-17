#!/bin/bash

# backup the convex database
mkdir -p backups
npx --yes convex export --include-file-storage --path ./backups/backup.zip