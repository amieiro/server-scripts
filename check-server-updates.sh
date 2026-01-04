#!/bin/bash

################################################################################
# DESCRIPTION:
#   This script checks for pending OS updates and packages that can be 
#   removed (autoremove) on Debian/Ubuntu based systems. It reports findings 
#   to Slack via Webhook or prints to the console.
#
# USAGE:
#   sudo ./check-server-updates.sh [no-webhook]
#
# PARAMETERS:
#   1. no-webhook: Optional flag to disable Slack notifications and 
#      display the output only in the terminal.
#
# DEFAULT VALUES:
#   - SEND_WEBHOOK: true
#   - PING_USERS: "user1 user2"
################################################################################

# --- Load Configuration ---
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="${SCRIPT_DIR}/config.sh"

if [ ! -f "$CONFIG_FILE" ]; then
    echo "Error: Configuration file not found at $CONFIG_FILE"
    echo "Please copy config.sh.example to config.sh and configure it."
    exit 1
fi

source "$CONFIG_FILE"

# --- Configuration Constants ---
SERVER_NAME="$CHECK_SERVER_UPDATES_SERVER_NAME"
SLACK_WEBHOOK_URL="$CHECK_SERVER_UPDATES_SLACK_WEBHOOK_URL"
PING_USERS="$CHECK_SERVER_UPDATES_PING_USERS"

# --- Initialization ---
# Ensure the script is run as root
if [[ $EUID -ne 0 ]]; then
   echo "This script must be run as root (use sudo)."
   exit 1
fi

SEND_WEBHOOK=true

# --- Argument Parsing ---
for arg in "$@"; do
    # Disable Slack notifications if requested
    if [ "$arg" == "no-webhook" ]; then
        SEND_WEBHOOK=false
    fi
done

# --- Check for Updates ---
# Update package lists first
apt-get update -qq

# Count upgradable packages
# We filter the output of apt-get upgrade --just-print
UPDATES_LIST=$(apt-get --just-print upgrade | grep "^Inst" | awk '{print $2}')
UPDATE_COUNT=$(echo "$UPDATES_LIST" | grep -v "^$" | wc -l | xargs)

# Count packages that can be autoremoved
REMOVE_COUNT=$(apt-get --just-print autoremove | grep "^Remv" | wc -l | xargs)

# Check if a reboot is required (common in Ubuntu/Debian after kernel updates)
REBOOT_REQUIRED=false
if [ -f /var/run/reboot-required ]; then
    REBOOT_REQUIRED=true
fi

# --- Slack Formatting ---
# Build user mentions
MENTIONS=""
for user in $PING_USERS; do
    MENTIONS+="<@$user> "
done

# Determine status and visuals
if [ "$UPDATE_COUNT" -gt 0 ] || [ "$REMOVE_COUNT" -gt 0 ] || [ "$REBOOT_REQUIRED" = true ]; then
    EMOJI="🚨"
    COLOR="#E01E5A" # Slack Red
    TITLE="Action Required: System updates available"
    
    # Detail string construction
    DETAILS="• *Pending Updates:* $UPDATE_COUNT packages\n"
    DETAILS+="• *Obsolete Packages:* $REMOVE_COUNT can be removed\n"
    
    if [ "$REBOOT_REQUIRED" = true ]; then
        DETAILS+="• *Reboot:* ⚠️ System reboot is REQUIRED\n"
    fi
    
    FINAL_TEXT="$DETAILS\nAttention: $MENTIONS"
else
    EMOJI="✅"
    COLOR="#36a64f" # Slack Green
    TITLE="System is up to date"
    FINAL_TEXT="No pending updates or packages to remove."
fi

# --- Output Delivery ---
if [ "$SEND_WEBHOOK" = true ]; then
    # Create JSON payload
    PAYLOAD=$(cat <<EOF
{
  "text": "$EMOJI *Server Update Report - $SERVER_NAME*",
  "attachments": [
    {
      "color": "$COLOR",
      "title": "$TITLE",
      "text": "${FINAL_TEXT}",
      "footer": "Check executed on: $(date '+%Y-%m-%d %H:%M:%S')"
    }
  ]
}
EOF
)
    # Send to Slack
    curl -s -X POST -H 'Content-type: application/json' --data "$PAYLOAD" "$SLACK_WEBHOOK_URL" > /dev/null
    echo "Update report sent to Slack."
else
    # Output to console
    echo "--- CHECK SERVER UPDATES ($SERVER_NAME) ---"
    echo -e "Status: $EMOJI $TITLE"
    echo -e "Details:\n$FINAL_TEXT"
    echo "-------------------------------------------"
fi