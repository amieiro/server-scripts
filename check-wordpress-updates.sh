#!/bin/bash

################################################################################
# DESCRIPTION:
#   Checks WordPress installations for pending updates and sends alerts.
#   Reports updates for core, plugins, themes, and translations with severity levels.
#
# USAGE:
#   sudo ./check-wordpress-updates.sh [no-webhook]
#
# PARAMETERS:
#   1. no-webhook: Optional flag to disable webhook notifications and 
#      display the output only in the terminal.
#
# SEVERITY LEVELS:
#   - CRITICAL (🚨 red): Core, plugin, or theme updates available
#   - INFO (✅ green): Only translation updates or no updates pending
#
# DEFAULT VALUES:
#   - WP_ROOT: Configured in config.sh (references WP_UPDATE_WP_ROOT)
#   - SEND_WEBHOOK: true
################################################################################

# --- Load Common Functions (includes auto-update) ---
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/common-functions.sh"

# --- Load Configuration ---
CONFIG_FILE="${SCRIPT_DIR}/config.sh"

if [ ! -f "$CONFIG_FILE" ]; then
    echo "Error: Configuration file not found at $CONFIG_FILE"
    echo "Please copy config.sh.example to config.sh and configure it."
    exit 1
fi

source "$CONFIG_FILE"

# --- Initialization & Tool Check ---
# Ensure script runs as root
if [[ $EUID -ne 0 ]]; then
   echo "This script must be run as root (use sudo)."
   exit 1
fi

# Verify WP-CLI is installed
WP_CLI="${WP_UPDATE_WP_CLI}"
if ! command -v $WP_CLI &> /dev/null; then
    echo "Error: 'wp-cli' is not installed."
    exit 1
fi

WP_ROOT="$CHECK_WORDPRESS_UPDATES_WP_ROOT"
SEND_WEBHOOK=true

# --- Argument Parsing ---
for arg in "$@"; do
    if [ "$arg" == "no-webhook" ]; then 
        SEND_WEBHOOK=false
    fi
done

# --- Counters and Report ---
TOTAL_SITES=0
CRITICAL_SITES=0
INFO_SITES=0
NO_UPDATES_SITES=0
CONNECTION_FAILED_SITES=0
REPORT_LIST=""
CONNECTION_FAILED_LIST=""

# --- Find WordPress Installations ---
echo "Finding WordPress installations in $WP_ROOT..."

# Find directories containing wp-includes (WordPress installations)
while read -r wp_includes_dir; do
    WP_PATH=$(dirname "$wp_includes_dir")
    ((TOTAL_SITES++))
    
    # Get WordPress owner
    WP_OWNER=$(stat -c '%U' "$WP_PATH" 2>/dev/null || stat -f '%Su' "$WP_PATH" 2>/dev/null)
    
    if [ -z "$WP_OWNER" ]; then
        echo "Warning: Could not determine owner for $WP_PATH"
        continue
    fi
    
    # Get site URL (optional, might fail)
    SITE_URL=$(sudo -u "$WP_OWNER" "$WP_CLI" option get siteurl --path="$WP_PATH" 2>/dev/null || echo "")
    
    # Check database connection
    DB_CHECK=$(sudo -u "$WP_OWNER" "$WP_CLI" db check --path="$WP_PATH" 2>&1)
    if [ $? -ne 0 ]; then
        DISPLAY_NAME="${SITE_URL:-$WP_PATH}"
        echo "Warning: Database connection failed for $DISPLAY_NAME (Path: $WP_PATH)"
        ((CONNECTION_FAILED_SITES++))
        if [ -n "$SITE_URL" ]; then
            CONNECTION_FAILED_LIST+="   • \`${WP_PATH}\` - ${SITE_URL}\n"
        else
            CONNECTION_FAILED_LIST+="   • \`${WP_PATH}\`\n"
        fi
        continue
    fi
    
    # Initialize counters for this site
    CORE_UPDATES=0
    PLUGIN_UPDATES=0
    THEME_UPDATES=0
    TRANSLATION_UPDATES=0
    DETAILS=""
    
    # --- Check Core Updates ---
    CORE_UPDATE_INFO=$(sudo -u "$WP_OWNER" "$WP_CLI" core check-update --format=json --path="$WP_PATH" 2>/dev/null)
    if [ -n "$CORE_UPDATE_INFO" ] && [ "$CORE_UPDATE_INFO" != "[]" ]; then
        CORE_UPDATES=$(echo "$CORE_UPDATE_INFO" | grep -c "version" 2>/dev/null || echo "0")
        CORE_UPDATES=$(echo "$CORE_UPDATES" | tr -d '[:space:]')  # Remove all whitespace
        if [ -n "$CORE_UPDATES" ] && [ "$CORE_UPDATES" -gt 0 ] 2>/dev/null; then
            CURRENT_VERSION=$(sudo -u "$WP_OWNER" "$WP_CLI" core version --path="$WP_PATH" 2>/dev/null)
            LATEST_VERSION=$(echo "$CORE_UPDATE_INFO" | grep -o '"version":"[^"]*"' | head -1 | cut -d'"' -f4)
            DETAILS+="   • *Core*: $CURRENT_VERSION → $LATEST_VERSION\n"
        else
            CORE_UPDATES=0
        fi
    fi
    
    # --- Check Plugin Updates ---
    PLUGIN_UPDATE_LIST=$(sudo -u "$WP_OWNER" "$WP_CLI" plugin list --update=available --format=csv --fields=name,version,update_version --path="$WP_PATH" 2>/dev/null)
    if [ -n "$PLUGIN_UPDATE_LIST" ]; then
        # Count only valid lines (skip header and error messages)
        PLUGIN_UPDATES=$(echo "$PLUGIN_UPDATE_LIST" | tail -n +2 | grep -v "^Warning:" | grep -v "^Fatal error:" | grep -v "^Error:" | grep -c "," 2>/dev/null || echo "0")
        PLUGIN_UPDATES=$(echo "$PLUGIN_UPDATES" | tr -d '[:space:]')  # Remove all whitespace
        if [ -n "$PLUGIN_UPDATES" ] && [ "$PLUGIN_UPDATES" -gt 0 ] 2>/dev/null; then
            DETAILS+="   • *Plugins* ($PLUGIN_UPDATES):\n"
            while IFS=',' read -r name version update_version; do
                # Skip header, empty lines, and error messages
                if [ "$name" != "name" ] && [ -n "$name" ] && [[ ! "$name" =~ ^(Warning|Fatal|Error|Stack) ]]; then
                    DETAILS+="     - $name: $version → $update_version\n"
                fi
            done <<< "$PLUGIN_UPDATE_LIST"
        else
            PLUGIN_UPDATES=0
        fi
    fi
    
    # --- Check Theme Updates ---
    THEME_UPDATE_LIST=$(sudo -u "$WP_OWNER" "$WP_CLI" theme list --update=available --format=csv --fields=name,version,update_version --path="$WP_PATH" 2>/dev/null)
    if [ -n "$THEME_UPDATE_LIST" ]; then
        # Count only valid lines (skip header and error messages)
        THEME_UPDATES=$(echo "$THEME_UPDATE_LIST" | tail -n +2 | grep -v "^Warning:" | grep -v "^Fatal error:" | grep -v "^Error:" | grep -c "," 2>/dev/null || echo "0")
        THEME_UPDATES=$(echo "$THEME_UPDATES" | tr -d '[:space:]')  # Remove all whitespace
        if [ -n "$THEME_UPDATES" ] && [ "$THEME_UPDATES" -gt 0 ] 2>/dev/null; then
            DETAILS+="   • *Themes* ($THEME_UPDATES):\n"
            while IFS=',' read -r name version update_version; do
                # Skip header, empty lines, and error messages
                if [ "$name" != "name" ] && [ -n "$name" ] && [[ ! "$name" =~ ^(Warning|Fatal|Error|Stack) ]]; then
                    DETAILS+="     - $name: $version → $update_version\n"
                fi
            done <<< "$THEME_UPDATE_LIST"
        else
            THEME_UPDATES=0
        fi
    fi
    
    # --- Check Translation Updates ---
    # Note: WP-CLI doesn't have a direct command to check translation updates
    # We'll use language core update which will show if updates are available
    TRANSLATION_CHECK=$(sudo -u "$WP_OWNER" "$WP_CLI" language core update --dry-run --path="$WP_PATH" 2>/dev/null)
    if echo "$TRANSLATION_CHECK" | grep -q "Success: Translations are up to date"; then
        TRANSLATION_UPDATES=0
    else
        # Count lines that indicate updates
        TRANSLATION_UPDATES=$(echo "$TRANSLATION_CHECK" | grep -c "Updating" 2>/dev/null || echo "0")
        TRANSLATION_UPDATES=$(echo "$TRANSLATION_UPDATES" | tr -d '[:space:]')  # Remove all whitespace
        if [ -n "$TRANSLATION_UPDATES" ] && [ "$TRANSLATION_UPDATES" -gt 0 ] 2>/dev/null; then
            DETAILS+="   • *Translations*: $TRANSLATION_UPDATES update(s) available\n"
        else
            TRANSLATION_UPDATES=0
        fi
    fi
    
    # --- Determine Severity Level ---
    SEVERITY=""
    if [ "$CORE_UPDATES" -gt 0 ] || [ "$PLUGIN_UPDATES" -gt 0 ] || [ "$THEME_UPDATES" -gt 0 ]; then
        SEVERITY="CRITICAL"
        ((CRITICAL_SITES++))
    elif [ "$TRANSLATION_UPDATES" -gt 0 ]; then
        SEVERITY="INFO"
        ((INFO_SITES++))
    else
        # No updates at all
        ((NO_UPDATES_SITES++))
        continue  # Skip sites with no updates
    fi
    
    # --- Build Report Entry ---
    SITE_HEADER=""
    if [ -n "$SITE_URL" ]; then
        SITE_HEADER="*${SITE_URL}*"
    else
        SITE_HEADER="*${WP_PATH}*"
    fi
    
    REPORT_LIST+="\n${SITE_HEADER}\n"
    REPORT_LIST+="   📁 Path: \`${WP_PATH}\`\n"
    REPORT_LIST+="$DETAILS"
    
done < <(find "$WP_ROOT" -type d -name "wp-includes" -print 2>/dev/null)

# --- Build Final Report ---
SUMMARY="*Total Sites:* $TOTAL_SITES | *Critical:* $CRITICAL_SITES | *Info:* $INFO_SITES | *Up-to-date:* $NO_UPDATES_SITES | *Connection Failed:* $CONNECTION_FAILED_SITES"

# Add connection failed sites to report if any
if [ "$CONNECTION_FAILED_SITES" -gt 0 ]; then
    REPORT_LIST+="\n\n⚠️ *Sites with connection issues ($CONNECTION_FAILED_SITES):*\n$CONNECTION_FAILED_LIST"
fi

# Determine overall status
if [ "$CRITICAL_SITES" -gt 0 ]; then
    EMOJI="🚨"
    COLOR="#E01E5A"  # Red
    TITLE="Critical: WordPress updates available"
    # Build user mentions for critical alerts
    MENTIONS=""
    for user in $CHECK_WORDPRESS_UPDATES_PING_USERS; do
        MENTIONS+="<@$user> "
    done
    FINAL_TEXT="$SUMMARY\n\n$REPORT_LIST\n\nAttention: $MENTIONS"
elif [ "$INFO_SITES" -gt 0 ]; then
    EMOJI="✅"
    COLOR="#36A64F"  # Green
    TITLE="Info: Only translation updates available"
    FINAL_TEXT="$SUMMARY\n\n$REPORT_LIST"
else
    # All sites are up to date
    EMOJI="✅"
    COLOR="#36A64F"  # Green
    TITLE="All WordPress sites are up to date"
    FINAL_TEXT="$SUMMARY\n\nAll $TOTAL_SITES WordPress installation(s) are running the latest versions."
fi

# --- Output Delivery ---
if [ "$SEND_WEBHOOK" = true ]; then
    PAYLOAD=$(cat <<EOF
{
  "text": "$EMOJI *WordPress Audit - $CHECK_WORDPRESS_UPDATES_SERVER_NAME*",
  "attachments": [{
      "color": "$COLOR",
      "title": "$TITLE",
      "text": "$FINAL_TEXT",
      "footer": "Last check: $(date '+%Y-%m-%d %H:%M:%S')"
  }]
}
EOF
)
    curl -s -X POST -H 'Content-type: application/json' --data "$PAYLOAD" "$CHECK_WORDPRESS_UPDATES_SLACK_WEBHOOK_URL" > /dev/null
    echo "Report sent to webhook."
else
    echo -e "\n$EMOJI WordPress Audit - $CHECK_WORDPRESS_UPDATES_SERVER_NAME"
    echo -e "Summary: $SUMMARY"
    echo -e "$REPORT_LIST"
fi
