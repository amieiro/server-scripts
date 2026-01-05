#!/bin/bash

################################################################################
# DESCRIPTION:
#   This script recursively searches for Git repositories and checks for 
#   modified or untracked files. It can output results to the console or 
#   send a formatted report to a Slack channel via Webhook.
#
# USAGE:
#   ./git_check_report.sh [DIRECTORY] [include-vendor] [include-node-modules] [no-webhook]
#
# PARAMETERS:
#   1. DIRECTORY: The root path to start the search. (Default: /home)
#   2. include-vendor: Flag to include repositories inside "vendor" folders.
#   3. include-node-modules: Flag to include repositories inside "node_modules".
#   4. no-webhook: Flag to disable Slack notification and print to console.
#
# DEFAULT VALUES:
#   - SEARCH_DIR: /home
#   - INCLUDE_VENDOR: false
#   - INCLUDE_NODE_MODULES: false
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

# --- Initialization ---
SEARCH_DIR="$CHECK_GIT_STATUS_DEFAULT_SEARCH_DIR"
INCLUDE_VENDOR=false
INCLUDE_NODE_MODULES=false
SEND_WEBHOOK=true

# --- Argument Parsing ---
for arg in "$@"; do
    # Check for include-vendor flag
    if [ "$arg" == "include-vendor" ]; then
        INCLUDE_VENDOR=true
    # Check for include-node-modules flag
    elif [ "$arg" == "include-node-modules" ]; then
        INCLUDE_NODE_MODULES=true
    # Check for no-webhook flag
    elif [ "$arg" == "no-webhook" ]; then
        SEND_WEBHOOK=false
    # Identify if the argument is a path
    elif [[ "$arg" == /* ]]; then
        SEARCH_DIR="$arg"
    fi
done

# --- Status Tracking ---
REPORT_CONTENT=""
TOTAL_REPOS=0
CHANGED_REPOS=0

# --- Start Scanning ---
# Use find to locate .git directories and prune them to avoid nested searches
while read -r gitdir; do
    # Identify the repository root
    repo_path=$(dirname "$gitdir")
    ((TOTAL_REPOS++))
    
    # Filter vendor directories unless requested
    if [[ "$repo_path" == *"/vendor/"* || "$repo_path" == *"/vendor" ]] && [ "$INCLUDE_VENDOR" = false ]; then
        continue
    fi

    # Filter node_modules directories unless requested
    if [[ "$repo_path" == *"/node_modules/"* || "$repo_path" == *"/node_modules" ]] && [ "$INCLUDE_NODE_MODULES" = false ]; then
        continue
    fi

    # Handle git security ownership issues
    if ! git config --global --get-all safe.directory | grep -qFx "$repo_path"; then
        git config --global --add safe.directory "$repo_path"
    fi

    # Capture the output of git status
    status_output=$(git -C "$repo_path" status --porcelain 2>/dev/null)
    
    # Extract modified and untracked counts
    modified=$(echo "$status_output" | grep -v "^??" | grep -v "^$" | wc -l | xargs)
    untracked=$(echo "$status_output" | grep "^??" | wc -l | xargs)

    # Accumulate data if the repository has changes
    if [ "$modified" -gt 0 ] || [ "$untracked" -gt 0 ]; then
        ((CHANGED_REPOS++))
        REPORT_CONTENT+="\n• \`${repo_path}\`\n   └ Modified: $modified | Untracked: $untracked"
    fi

done < <(find "$SEARCH_DIR" -name ".git" -type d -prune)

# --- Slack Formatting ---
# Build user mentions string
MENTIONS=""
for user in $CHECK_GIT_STATUS_PING_USERS; do
    MENTIONS+="<@$user> "
done

# Define UI elements based on the scan result
if [ "$CHANGED_REPOS" -gt 0 ]; then
    EMOJI="🚨"
    STATUS_MSG="Changes detected in $CHANGED_REPOS of $TOTAL_REPOS repositories."
    COLOR="#E8A317"
    FINAL_TEXT="$REPORT_CONTENT\n\nAttention: $MENTIONS"
else
    EMOJI="✅"
    STATUS_MSG="All $TOTAL_REPOS repositories are clean."
    COLOR="#36a64f"
    FINAL_TEXT="No modified or untracked files found."
fi

# --- Output Delivery ---
if [ "$SEND_WEBHOOK" = true ]; then
    # Prepare JSON payload for Slack API
    PAYLOAD=$(cat <<EOF
{
  "text": "$EMOJI *Git Status Report - Server: $CHECK_GIT_STATUS_SERVER_NAME*",
  "attachments": [
    {
      "color": "$COLOR",
      "title": "$STATUS_MSG",
      "text": "${FINAL_TEXT}",
      "footer": "Automatic check: $(date '+%Y-%m-%d %H:%M:%S')"
    }
  ]
}
EOF
)
    # Execute the curl request
    curl -s -X POST -H 'Content-type: application/json' --data "$PAYLOAD" "$CHECK_GIT_STATUS_SLACK_WEBHOOK_URL" > /dev/null
    echo "Report sent to Slack."
else
    # Output to stdout if webhook is disabled
    echo "--- GIT CHECK REPORT ($CHECK_GIT_STATUS_SERVER_NAME) ---"
    echo -e "Status: $EMOJI $STATUS_MSG"
    echo -e "Details: $FINAL_TEXT"
    echo "---------------------------------------"
fi