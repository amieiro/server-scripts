#!/bin/bash

# --- Load Common Functions (includes auto-update) ---
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/common-functions.sh"

# This script performs a backup of WordPress sites, non-WordPress sites, and MySQL databases.
# It organizes backups into a directory structure based on the current date.

# Set variables
# BACKUP_DIR: Directory where backups will be stored, organized by date.
# MYSQL_ROOT_PASSWORD: MySQL root password for accessing databases.
# CURRENT_DATE_TIME: Timestamp used for naming backup files.

BACKUP_DIR="$(dirname "$0")/data/$(date +%Y-%m-%d)"
MYSQL_ROOT_PASSWORD="mysql-root-password" # Replace with your actual MySQL root password
CURRENT_DATE_TIME="$(date +%Y-%m-%d-%H-%M)"

# List of non-WordPress sites to back up
# NON_WORDPRESS_SITES: Array containing absolute paths to the root directories of non-WordPress sites.

NON_WORDPRESS_SITES=(
  "/var/www/my-laravel-site" # Replace with actual paths
)

# Create the backup directory if it doesn't exist
# Ensures the backup directory is available before proceeding with backups.

mkdir -p "$BACKUP_DIR"

# Find all wp-config.php files and back up their directories
# Searches for WordPress configuration files and backs up their parent directories.
# Each backup is compressed into a tar.gz file named with the current timestamp and directory path.

find / -type f -name "wp-config.php" 2>/dev/null | while read -r CONFIG_FILE; do
  WP_DIR="$(dirname "$CONFIG_FILE")"
  TAR_NAME="${CURRENT_DATE_TIME}-$(echo "$WP_DIR" | tr '/' '-').tar.gz"
  tar -czvf "$BACKUP_DIR/$TAR_NAME" -C "$(dirname "$WP_DIR")" "$(basename "$WP_DIR")"
  echo "Backed up WordPress directory: $WP_DIR"
done

# Back up non-WordPress sites
# Iterates through the list of non-WordPress site directories and backs them up.
# Each backup is compressed into a tar.gz file named with the current timestamp and directory path.
# If a directory is not found, a warning is displayed.

for SITE_DIR in "${NON_WORDPRESS_SITES[@]}"; do
  if [ -d "$SITE_DIR" ]; then
    TAR_NAME="${CURRENT_DATE_TIME}-$(echo "$SITE_DIR" | tr '/' '-').tar.gz"
    tar -czvf "$BACKUP_DIR/$TAR_NAME" -C "$(dirname "$SITE_DIR")" "$(basename "$SITE_DIR")"
    echo "Backed up non-WordPress site: $SITE_DIR"
  else
    echo "Warning: Non-WordPress site directory not found: $SITE_DIR"
  fi
done

# Back up all MySQL databases
# Retrieves a list of all MySQL databases excluding system databases.
# Each database is backed up into a compressed SQL file named with the current timestamp and database name.

DATABASES=$(mysql -u root -p"$MYSQL_ROOT_PASSWORD" -e "SHOW DATABASES;" | grep -Ev "^(Database|information_schema|performance_schema|mysql|sys)$")
for DB in $DATABASES; do
  DB_BACKUP_NAME="${CURRENT_DATE_TIME}-$DB.sql.gz"
  mysqldump -u root -p"$MYSQL_ROOT_PASSWORD" "$DB" | gzip > "$BACKUP_DIR/$DB_BACKUP_NAME"
  echo "Backed up database: $DB"
done

echo "Backup completed. All files are in: $BACKUP_DIR"
