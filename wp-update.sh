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
    SITE_NAME=$(basename "$WP_PATH")
    echo "------------------------------------------" >> "$LOG_FILE"
    echo "🚀 Updating ${CURRENT_SITE} of ${TOTAL_SITES} installations: ${SITE_NAME}" >> "$LOG_FILE"

    CURRENT_VERSION=$(grep -o "wp_version = '[0-9.]*'" "$WP_PATH/wp-includes/version.php" | cut -d "'" -f 2)
    WP_OWNER=$(stat -c '%U' "$WP_PATH")
    WP_GROUP=$(stat -c '%G' "$WP_PATH")

    echo "📌 Current version: $CURRENT_VERSION" >> "$LOG_FILE"
    echo "👤 Owner: $WP_OWNER:$WP_GROUP" >> "$LOG_FILE"

    # Backup if enabled
    if [ "$ENABLE_BACKUPS" = true ]; then
        echo "📦 Creating backup for site: $SITE_NAME" >> "$LOG_FILE"
        DB_BACKUP_FILE="${DAILY_BACKUP_DIR}/${SITE_NAME}-db.sql"
        FILES_BACKUP_FILE="${DAILY_BACKUP_DIR}/${SITE_NAME}-files.tar.gz"

        sudo -u "$WP_OWNER" "$WP_CLI" db export "$DB_BACKUP_FILE"  --skip-plugins --skip-themes --path="$WP_PATH" >>"$LOG_FILE" 2>&1 || echo "🚨 Error exporting database for ${SITE_NAME}" >>"$LOG_FILE"
        tar -czf "$FILES_BACKUP_FILE" -C "$WP_PATH" . >>"$LOG_FILE" 2>&1 || echo "🚨 Error backing up files for ${SITE_NAME}" >>"$LOG_FILE"
    else
        echo "⏩ Backups are disabled. Skipping backup for site: $SITE_NAME" >>"$LOG_FILE"
    fi

    # Update core and database
    echo "🔄 Updating WordPress core..." >>"$LOG_FILE"
    sudo -u "$WP_OWNER" "$WP_CLI" core update  --skip-plugins --skip-themes --path="$WP_PATH" >>"$LOG_FILE" 2>&1 || echo "🚨 Error updating core for ${SITE_NAME}" >>"$LOG_FILE"
    sudo -u "$WP_OWNER" "$WP_CLI" core update-db  --skip-plugins --skip-themes --path="$WP_PATH" >>"$LOG_FILE" 2>&1 || echo "🚨 Error updating DB for ${SITE_NAME}" >>"$LOG_FILE"

    # Update plugins and themes
    echo "🔄 Updating plugins..." >>"$LOG_FILE"
    sudo -u "$WP_OWNER" "$WP_CLI" plugin update --all  --skip-plugins --skip-themes --path="$WP_PATH" >>"$LOG_FILE" 2>&1 || echo "🚨 Error updating plugins for ${SITE_NAME}" >>"$LOG_FILE"

    echo "🔄 Updating themes..." >>"$LOG_FILE"
    sudo -u "$WP_OWNER" "$WP_CLI" theme update --all  --skip-plugins --skip-themes --path="$WP_PATH" >>"$LOG_FILE" 2>&1 || echo "🚨 Error updating themes for ${SITE_NAME}" >>"$LOG_FILE"

    # Update translations
    echo "🌐 Updating translations..." >>"$LOG_FILE"
    sudo -u "$WP_OWNER" "$WP_CLI" language core update  --skip-plugins --skip-themes --path="$WP_PATH">>"$LOG_FILE" 2>&1 || echo "🚨 Error updating core translations for ${SITE_NAME}" >>"$LOG_FILE"
    sudo -u "$WP_OWNER" "$WP_CLI" language plugin update  --skip-plugins --skip-themes --all --path="$WP_PATH">>"$LOG_FILE" 2>&1 || echo "🚨 Error updating plugin translations for ${SITE_NAME}" >>"$LOG_FILE"
    sudo -u "$WP_OWNER" "$WP_CLI" language theme update  --skip-plugins --skip-themes --all --path="$WP_PATH">>"$LOG_FILE" 2>&1 || echo "🚨 Error updating theme translations for ${SITE_NAME}" >>"$LOG_FILE"

    # Remove inactive plugins/themes if enabled
    if [ "$REMOVE_INACTIVE_PLUGINS" = true ]; then
        INACTIVE_PLUGINS=$(sudo -u $WP_OWNER $WP_CLI plugin list --status=inactive --field=name --path="$WP_PATH" --skip-plugins --skip-themes)
        if [ ! -z "${INACTIVE_PLUGINS}" ]; then
            sudo -u $WP_OWNER $WP_CLI plugin delete ${INACTIVE_PLUGINS} --skip-plugins --skip-themes --path="$WP_PATH"  --skip-plugins --skip-themes>>"$LOG_FILE" 2>&1 || echo "🚨 Error removing inactive plugins for ${SITE_NAME}" >>"$LOG_FILE"
        fi
    fi

    if [ "$REMOVE_INACTIVE_THEMES" = true ]; then
        INACTIVE_THEMES=$(sudo -u $WP_OWNER $WP_CLI theme list --status=inactive --field=name --path="$WP_PATH"  --skip-plugins --skip-themes)
        if [ ! -z "${INACTIVE_THEMES}" ]; then
            sudo -u $WP_OWNER $WP_CLI theme delete ${INACTIVE_THEMES} --path="$WP_PATH"  --skip-plugins --skip-themes>>"$LOG_FILE" 2>&1 || echo "🚨 Error removing inactive themes for ${SITE_NAME}" >>"$LOG_FILE"
        fi
    fi

    # Fix permissions
    chown -R "${WP_OWNER}:${WP_GROUP}" "${WP_PATH}">>"${LOG_FILE}" 2>&1 || echo "🚨 Error setting permissions for ${SITE_NAME}" >>"${LOG_FILE}"

    echo "✅ Completed processing $SITE_NAME at $(date)" >>"${LOG_FILE}"

    CURRENT_SITE=$((CURRENT_SITE + 1))
done

# Cleanup old backups
echo "🧹 Cleaning backups older than ${BACKUP_RETENTION_DAYS} days...">>"${LOG_FILE}"
find "${BACKUP_DIR}" -maxdepth 1 -type d -name 'wp-*' -mtime +"${BACKUP_RETENTION_DAYS}" -exec rm -rf {} \;>>"${LOG_FILE}" 2>&1 || echo "🚨 Error cleaning old backups">>"${LOG_FILE}"

# ----------------------------
# Calculate and log execution time
# ----------------------------

END_TIME=$(date +%s) # Capture script end time
EXECUTION_TIME=$((END_TIME - START_TIME))

HOURS=$((EXECUTION_TIME / 3600))
MINUTES=$(((EXECUTION_TIME % 3600) / 60))
SECONDS=$((EXECUTION_TIME % 60))

echo "⏱️ Total Execution Time: ${HOURS}h ${MINUTES}m ${SECONDS}s" >> "${LOG_FILE}"

# ----------------------------
# Script Completion Log Entry
# ----------------------------

echo "==========================================" >> "${LOG_FILE}"
echo "🎉 WordPress Update Script Completed: $(date)" >> "${LOG_FILE}"
echo "==========================================" >> "${LOG_FILE}"