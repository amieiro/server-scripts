#!/bin/bash

################################################################################
# DESCRIPTION:
#   Scans for PHP (Composer) and JS (NPM/Yarn) vulnerabilities.
#   Handles missing/corrupt lock files, non-git projects, and root execution.
#
# USAGE:
#   sudo ./check-app-vulnerabilities.sh [DIRECTORY] [include-vendor] 
#                                       [include-node-modules] [show-missing-lock-file] [no-webhook]
#
# PARAMETERS:
#   1. DIRECTORY: Root path to scan. (Default: /home)
#   2. include-vendor: Scan inside "vendor" folders.
#   3. include-node-modules: Scan inside "node_modules" folders.
#   4. show-missing-lock-file: Show projects that lack a lock file (hidden by default).
#   5. no-webhook: Console output only.
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

# --- Initialization & Tool Check ---
# Ensure script runs as root
if [[ $EUID -ne 0 ]]; then
   echo "This script must be run as root (use sudo)."
   exit 1
fi

# Bypass Composer root warning
export COMPOSER_ALLOW_SUPERUSER=1

# Verify dependencies
for tool in composer npm jq; do
    if ! command -v $tool &> /dev/null; then
        echo "Error: '$tool' is not installed."
        exit 1
    fi
done

SEARCH_DIR="$CHECK_APP_VULNERABILITIES_DEFAULT_SEARCH_DIR"
INCLUDE_VENDOR=false
INCLUDE_NODE_MODULES=false
SHOW_MISSING_LOCK=false
SEND_WEBHOOK=true

# --- Argument Parsing ---
for arg in "$@"; do
    if [ "$arg" == "include-vendor" ]; then INCLUDE_VENDOR=true;
    elif [ "$arg" == "include-node-modules" ]; then INCLUDE_NODE_MODULES=true;
    elif [ "$arg" == "show-missing-lock-file" ]; then SHOW_MISSING_LOCK=true;
    elif [ "$arg" == "no-webhook" ]; then SEND_WEBHOOK=false;
    elif [[ "$arg" == /* ]]; then SEARCH_DIR="$arg"; fi
done

# --- Counters ---
C_CRITICAL=0; C_HIGH=0; C_MEDIUM=0; C_LOW=0
N_CRITICAL=0; N_HIGH=0; N_MODERATE=0; N_LOW=0
REPORT_LIST=""

# --- Build Find Command Filters ---
FIND_EXCLUDE=""
[ "$INCLUDE_VENDOR" = false ] && FIND_EXCLUDE+=" -path '*/vendor' -prune -o"
[ "$INCLUDE_NODE_MODULES" = false ] && FIND_EXCLUDE+=" -path '*/node_modules' -prune -o"

# --- Scanning Logic ---
while read -r manifest_file; do
    
    project_path=$(dirname "$manifest_file")
    manifest_name=$(basename "$manifest_file")
    repo_issues=""
    has_issues=false

    # --- 1. COMPOSER AUDIT ---
    if [ "$manifest_name" == "composer.json" ]; then
        lock_file="$project_path/composer.lock"
        
        if [ ! -f "$lock_file" ]; then
            if [ "$SHOW_MISSING_LOCK" = true ]; then
                repo_issues+="Composer [Missing Lock File] "
                has_issues=true
            fi
        elif ! jq . "$lock_file" >/dev/null 2>&1; then
            repo_issues+="Composer [Corrupted Lock File] "
            has_issues=true
        else
            # Run audit as JSON
            audit_json=$(composer audit --working-dir="$project_path" --format=json 2>/dev/null)
            
            if [ -n "$audit_json" ] && [ "$audit_json" != "[]" ]; then
                crit=$(echo "$audit_json" | jq '[.. | .severity? | select(. == "critical")] | length')
                high=$(echo "$audit_json" | jq '[.. | .severity? | select(. == "high")] | length')
                med=$(echo "$audit_json" | jq '[.. | .severity? | select(. == "medium")] | length')
                low=$(echo "$audit_json" | jq '[.. | .severity? | select(. == "low")] | length')
                
                if [ $((crit+high+med+low)) -gt 0 ]; then
                    C_CRITICAL=$((C_CRITICAL + crit))
                    C_HIGH=$((C_HIGH + high))
                    C_MEDIUM=$((C_MEDIUM + med))
                    C_LOW=$((C_LOW + low))
                    repo_issues+="Composer [C:$crit H:$high M:$med L:$low] "
                    has_issues=true
                fi
            fi
        fi
    fi

    # --- 2. NPM AUDIT ---
    if [ "$manifest_name" == "package.json" ]; then
        lock_npm="$project_path/package-lock.json"
        
        if [ ! -f "$lock_npm" ]; then
            if [ "$SHOW_MISSING_LOCK" = true ]; then
                repo_issues+="NPM [Missing Lock File] "
                has_issues=true
            fi
        elif ! jq . "$lock_npm" >/dev/null 2>&1; then
            repo_issues+="NPM [Corrupted Lock File] "
            has_issues=true
        else
            # Run npm audit
            npm_json=$(npm audit --prefix "$project_path" --json 2>/dev/null)
            
            if echo "$npm_json" | jq -e '.metadata.vulnerabilities' >/dev/null 2>&1; then
                crit=$(echo "$npm_json" | jq '.metadata.vulnerabilities.critical // 0')
                high=$(echo "$npm_json" | jq '.metadata.vulnerabilities.high // 0')
                mod=$(echo "$npm_json" | jq '.metadata.vulnerabilities.moderate // 0')
                low=$(echo "$npm_json" | jq '.metadata.vulnerabilities.low // 0')
                
                crit_sum=0; for i in $crit; do crit_sum=$((crit_sum + i)); done
                high_sum=0; for i in $high; do high_sum=$((high_sum + i)); done
                mod_sum=0; for i in $mod; do mod_sum=$((mod_sum + i)); done
                low_sum=0; for i in $low; do low_sum=$((low_sum + i)); done
                
                if [ $((crit_sum+high_sum+mod_sum+low_sum)) -gt 0 ]; then
                    N_CRITICAL=$((N_CRITICAL + crit_sum))
                    N_HIGH=$((N_HIGH + high_sum))
                    N_MODERATE=$((N_MODERATE + mod_sum))
                    N_LOW=$((N_LOW + low_sum))
                    repo_issues+="NPM [C:$crit_sum H:$high_sum M:$mod_sum L:$low_sum] "
                    has_issues=true
                fi
            fi
        fi
    fi

    # Append to report if issues were flagged
    if [ "$has_issues" = true ]; then
        REPORT_LIST+="\n• \`${project_path}\`\n  └ $repo_issues"
    fi

done < <(eval "find \"$SEARCH_DIR\" $FIND_EXCLUDE \( -name 'composer.json' -o -name 'package.json' \) -print")

# --- Result Reporting ---
TOTAL_CRITICAL=$((C_CRITICAL + N_CRITICAL))
TOTAL_HIGH=$((C_HIGH + N_HIGH))
TOTAL_MEDIUM_MOD=$((C_MEDIUM + N_MODERATE))
TOTAL_LOW=$((C_LOW + N_LOW))

if [ $((TOTAL_CRITICAL + TOTAL_HIGH)) -gt 0 ]; then
    EMOJI="🚨"; COLOR="#E01E5A"
    MENTIONS=""; for user in $CHECK_APP_VULNERABILITIES_PING_USERS; do MENTIONS+="<@$user> "; done
elif [ $((TOTAL_MEDIUM_MOD + TOTAL_LOW + C_CRITICAL + C_HIGH + N_CRITICAL + N_HIGH)) -gt 0 ] || [ -n "$REPORT_LIST" ]; then
    # Use warning emoji if there are medium/low issues OR if REPORT_LIST has items (like missing lock files)
    EMOJI="⚠️"; COLOR="#E8A317"; MENTIONS=""
else
    EMOJI="✅"; COLOR="#36A64F"; MENTIONS=""
fi

SUMMARY="*Composer:* crit:$C_CRITICAL, high:$C_HIGH, med:$C_MEDIUM, low:$C_LOW\n*NPM:* crit:$N_CRITICAL, high:$N_HIGH, mod:$N_MODERATE, low:$N_LOW"
[ -z "$REPORT_LIST" ] && REPORT_LIST="All project dependencies are secure."

if [ "$SEND_WEBHOOK" = true ]; then
    PAYLOAD=$(cat <<EOF
{
  "text": "$EMOJI *Security Audit - $CHECK_APP_VULNERABILITIES_SERVER_NAME*",
  "attachments": [{
      "color": "$COLOR",
      "title": "Vulnerability Summary",
      "text": "$SUMMARY",
      "fields": [{ "title": "Details", "value": "${REPORT_LIST}\n\n$MENTIONS" }],
      "footer": "Last check: $(date '+%Y-%m-%d %H:%M:%S')"
  }]
}
EOF
)
    curl -s -X POST -H 'Content-type: application/json' --data "$PAYLOAD" "$CHECK_APP_VULNERABILITIES_SLACK_WEBHOOK_URL" > /dev/null
    echo "Report sent to Slack."
else
    echo -e "--- SECURITY AUDIT ($CHECK_APP_VULNERABILITIES_SERVER_NAME) ---"
    echo -e "Summary:\n$SUMMARY"
    echo -e "\nDetailed List:$REPORT_LIST"
fi