#!/bin/bash

# --- Load Common Functions (includes auto-update) ---
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/common-functions.sh"

# ----------------------------
# Configuration Constants
# ----------------------------

WP_ROOT="/var/www" # Root directory containing all WordPress installations
WP_CLI="/usr/local/bin/wp" # Path to WP-CLI executable
LOG_FOLDER="/var/log/wp-update" # Log file directory
LOG_FILE="${LOG_FOLDER}/wp-update-$(date +%Y-%m-%d).log" # Daily log file path
BACKUP_DIR="/var/backups" # Root backup directory (daily subfolders)
BACKUP_RETENTION_DAYS=7 # Days to retain backups

# Feature Flags
ENABLE_BACKUPS=false # Perform database and file backups (default: false)
REMOVE_INACTIVE_PLUGINS=false # Remove inactive plugins (default: false)
REMOVE_INACTIVE_THEMES=true # Remove inactive themes (default: true)

# ----------------------------
# Initialization
# ----------------------------

START_TIME=$(date +%s) # Capture script start time

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

TOTAL_SITES=$(echo "$WP_INSTALLATIONS" | wc -l)
CURRENT_SITE=1

# ----------------------------
# Process Each Installation
# ----------------------------

for WP_PATH in $WP_INSTALLATIONS; do

    CURRENT_VERSION=$(grep -o "wp_version = '[0-9.]*'" "$WP_PATH/wp-includes/version.php" | cut -d "'" -f 2)
    WP_OWNER=$(stat -c '%U' "$WP_PATH")
    WP_GROUP=$(stat -c '%G' "$WP_PATH")

    SITE_URL=$(sudo -u "$WP_OWNER" "$WP_CLI" option get siteurl --path="$WP_PATH" 2>/dev/null)

    echo "------------------------------------------" >> "$LOG_FILE"
    echo "🚀 Updating ${CURRENT_SITE} of ${TOTAL_SITES} installations:" >> "$LOG_FILE"
    echo "📁 Path: ${WP_PATH}" >> "$LOG_FILE"
    if [ ! -z "${SITE_URL}" ]; then
        echo "🌐 URL: ${SITE_URL}" >> "$LOG_FILE"
    else
        echo "🌐 URL: 🚨 Unable to retrieve URL" >> "$LOG_FILE"
    fi

    echo "📌 Current version: $CURRENT_VERSION" >> "$LOG_FILE"
    echo "👤 Owner: $WP_OWNER:$WP_GROUP" >> "$LOG_FILE"

    # Backup if enabled
    if [ "$ENABLE_BACKUPS" = true ]; then
        echo "📦 Creating backup..." >> "$LOG_FILE"
        DB_BACKUP_FILE="${DAILY_BACKUP_DIR}/$(basename ${WP_PATH})-db.sql"
        FILES_BACKUP_FILE="${DAILY_BACKUP_DIR}/$(basename ${WP_PATH})-files.tar.gz"

        sudo -u "$WP_OWNER" "$WP_CLI" db export "$DB_BACKUP_FILE" --skip-plugins --skip-themes --path="$WP_PATH" >>"$LOG_FILE" 2>&1 || echo "🚨 Error exporting database for ${SITE_URL}" >>"$LOG_FILE"
        tar -czf "$FILES_BACKUP_FILE" -C "$WP_PATH" . >>"$LOG_FILE" 2>&1 || echo "🚨 Error backing up files for ${SITE_URL}" >>"$LOG_FILE"
    else
        echo "⏩ Backups are disabled. Skipping backup." >>"$LOG_FILE"
    fi

    # Update core and database
    echo "🔄 Updating WordPress core..." >>"$LOG_FILE"
    sudo -u "$WP_OWNER" "$WP_CLI" core update --skip-plugins --skip-themes --path="$WP_PATH">>"$LOG_FILE" 2>&1 || echo "🚨 Error updating core for ${SITE_URL}" >>"$LOG_FILE"
    sudo -u "$WP_OWNER" "$WP_CLI" core update-db --skip-plugins --skip-themes --path="$WP_PATH">>"$LOG_FILE" 2>&1 || echo "🚨 Error updating DB for ${SITE_URL}" >>"$LOG_FILE"

    # Update plugins and themes
    echo "🔄 Updating plugins..." >>"$LOG_FILE"
    sudo -u "$WP_OWNER" "$WP_CLI" plugin update --all --skip-plugins --skip-themes --path="$WP_PATH">>"$LOG_FILE" 2>&1 || echo "🚨 Error updating plugins for ${SITE_URL}" >>"$LOG_FILE"

    echo "🔄 Updating themes..." >>"$LOG_FILE"
    sudo -u "$WP_OWNER" "$WP_CLI" theme update --all --skip-plugins --skip-themes --path="$WP_PATH">>"$LOG_FILE" 2>&1 || echo "🚨 Error updating themes for ${SITE_URL}" >>"$LOG_FILE"

    # Update translations
    echo "🌐 Updating translations..." >>"$LOG_FILE"
    sudo -u "$WP_OWNER" "$WP_CLI" language core update --skip-plugins --skip-themes --path="$WP_PATH">>"$LOG_FILE" 2>&1 || echo "🚨 Error updating core translations for ${SITE_URL}" >>"$LOG_FILE"
    sudo -u "$WP_OWNER" "$WP_CLI" language plugin update --all --skip-plugins --skip-themes --path="$WP_PATH">>"$LOG_FILE" 2>&1 || echo "🚨 Error updating plugin translations for ${SITE_URL}" >>"$LOG_FILE"
    sudo -u "$WP_OWNER" "$WP_CLI" language theme update --all --skip-plugins --skip-themes --path="$WP_PATH">>"$LOG_FILE" 2>&1 || echo "🚨 Error updating theme translations for ${SITE_URL}" >>"$LOG_FILE"

    # Fix permissions
    chown -R "${WP_OWNER}:${WP_GROUP}" "${WP_PATH}">>"${LOG_FILE}" 2>&1 || echo "🚨 Error setting permissions for ${SITE_URL}" >>"${LOG_FILE}"

    echo "✅ Completed processing at $(date)" >>"${LOG_FILE}"

    CURRENT_SITE=$((CURRENT_SITE + 1))
done

# Cleanup old backups
echo "🧹 Cleaning backups older than ${BACKUP_RETENTION_DAYS} days...">>"${LOG_FILE}"
find "${BACKUP_DIR}" -maxdepth 1 -type d -name 'wp-*' -mtime +"${BACKUP_RETENTION_DAYS}" -exec rm -rf {} \;>>"${LOG_FILE}" 2>&1 || echo "🚨 Error cleaning old backups">>"${LOG_FILE}"

# Execution time calculation
END_TIME=$(date +%s)
EXECUTION_TIME=$((END_TIME - START_TIME))
HOURS=$((EXECUTION_TIME / 3600))
MINUTES=$(((EXECUTION_TIME % 3600) / 60))
SECONDS=$((EXECUTION_TIME % 60))
echo "⏱️ Total Execution Time: ${HOURS}h ${MINUTES}m ${SECONDS}s">>"${LOG_FILE}"

echo "==========================================" >>"${LOG_FILE}"
echo "🎉 WordPress Update Script Completed: $(date)" >>"${LOG_FILE}"
echo "==========================================" >>"${LOG_FILE}"
