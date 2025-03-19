#!/bin/bash

# ----------------------------
# Configuration Constants
# ----------------------------

WP_ROOT="/var/www" # Root directory containing all WordPress installations
WP_CLI="/usr/local/bin/wp" # Path to WP-CLI executable
LOG_FOLDER="/var/log/wp-update" # Log file directory
LOG_FILE="${LOG_FOLDER}/wp-update-$(date +%Y-%m-%d).log" # Log file path (daily logs)
BACKUP_DIR="/var/backups" # Root backup directory (will contain daily subfolders)
BACKUP_RETENTION_DAYS=7 # Number of days to retain backups

# ----------------------------
# Initialization
# ----------------------------

TODAY=$(date +%Y%m%d)
DAILY_BACKUP_DIR="${BACKUP_DIR}/wp-${TODAY}"
mkdir -p "$DAILY_BACKUP_DIR"

mkdir -p "$LOG_FOLDER"
touch "$LOG_FILE"

echo "==========================================" >> "$LOG_FILE"
echo "WordPress Update Script Started: $(date)" >> "$LOG_FILE"
echo "==========================================" >> "$LOG_FILE"

# ----------------------------
# Find WordPress Installations
# ----------------------------

echo "🔍 Finding WordPress installations..." >> "$LOG_FILE"
WP_INSTALLATIONS=$(find "$WP_ROOT" -type d -name "wp-includes" -print | sed 's/wp-includes$//')

if [ -z "$WP_INSTALLATIONS" ]; then
    echo "❌ No WordPress installations found." >> "$LOG_FILE"
    exit 1
fi

# ----------------------------
# Process Each Installation
# ----------------------------

for WP_PATH in $WP_INSTALLATIONS; do
    echo "------------------------------------------" >> "$LOG_FILE"
    echo "🚀 Processing WordPress at: $WP_PATH" >> "$LOG_FILE"

    # Get current WP version and file ownership
    CURRENT_VERSION=$(grep -o "wp_version = '[0-9.]*'" "$WP_PATH/wp-includes/version.php" | cut -d "'" -f 2)
    WP_OWNER=$(stat -c '%U' "$WP_PATH")
    WP_GROUP=$(stat -c '%G' "$WP_PATH")
    SITE_NAME=$(basename "$WP_PATH")

    echo "📌 Current version: $CURRENT_VERSION" >> "$LOG_FILE"
    echo "👤 Owner: $WP_OWNER:$WP_GROUP" >> "$LOG_FILE"

    # ----------------------------
    # Backup WordPress Installation
    # ----------------------------

    echo "📦 Creating backup for site: $SITE_NAME" >> "$LOG_FILE"

    DB_BACKUP_FILE="${DAILY_BACKUP_DIR}/${SITE_NAME}-db.sql"
    FILES_BACKUP_FILE="${DAILY_BACKUP_DIR}/${SITE_NAME}-files.tar.gz"

    # Export database
    sudo -u "$WP_OWNER" "$WP_CLI" db export "$DB_BACKUP_FILE" --path="$WP_PATH" >> "$LOG_FILE" 2>&1

    # Backup files
    tar -czf "$FILES_BACKUP_FILE" -C "$WP_PATH" . >> "$LOG_FILE" 2>&1

    # ----------------------------
    # Update WordPress Components
    # ----------------------------

    echo "🔄 Updating WordPress core..." >> "$LOG_FILE"
    sudo -u "$WP_OWNER" "$WP_CLI" core update --path="$WP_PATH" >> "$LOG_FILE" 2>&1
    sudo -u "$WP_OWNER" "$WP_CLI" core update-db --path="$WP_PATH" >> "$LOG_FILE" 2>&1

    echo "🔄 Updating plugins..." >> "$LOG_FILE"
    sudo -u "$WP_OWNER" "$WP_CLI" plugin update --all --path="$WP_PATH" >> "$LOG_FILE" 2>&1

    echo "🔄 Updating themes..." >> "$LOG_FILE"
    sudo -u "$WP_OWNER" "$WP_CLI" theme update --all --path="$WP_PATH" >> "$LOG_FILE" 2>&1

    echo "🌐 Updating translations..." >> "$LOG_FILE"
    sudo -u "$WP_OWNER" "$WP_CLI" language core update --path="$WP_PATH" >> "$LOG_FILE" 2>&1
    sudo -u "$WP_OWNER" "$WP_CLI" language plugin update --all --path="$WP_PATH" >> "$LOG_FILE" 2>&1
    sudo -u "$WP_OWNER" "$WP_CLI" language theme update --all --path="$WP_PATH" >> "$LOG_FILE" 2>&1

    # ----------------------------
    # Fix Permissions (if needed)
    # ----------------------------

    echo "🔑 Ensuring correct permissions..." >> "${LOG_FILE}"
    chown -R "${WP_OWNER}:${WP_GROUP}" "${WP_PATH}" >> "${LOG_FILE}" 2>&1

    echo "✅ Completed processing $SITE_NAME at $(date)" >> "${LOG_FILE}"
done

# ----------------------------
# Cleanup Old Backups
# ----------------------------

echo "🧹 Cleaning up backups older than ${BACKUP_RETENTION_DAYS} days..." >> "${LOG_FILE}"
find "${BACKUP_DIR}" -maxdepth 1 -type d -name 'wp-*' -mtime +"${BACKUP_RETENTION_DAYS}" -exec rm -rf {} \; >> "${LOG_FILE}" 2>&1

# ----------------------------
# Script Completion Log Entry
# ----------------------------

echo "==========================================" >> "${LOG_FILE}"
echo "🎉 WordPress Update Script Completed: $(date)" >> "${LOG_FILE}"
echo "==========================================" >> "${LOG_FILE}"
