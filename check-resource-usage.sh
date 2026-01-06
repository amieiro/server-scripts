#!/bin/bash

################################################################################
# DESCRIPTION:
#   Monitors system resource usage and sends alerts when thresholds are exceeded.
#   Currently monitors disk space usage. Future metrics are documented below.
#
# USAGE:
#   sudo ./check-resource-usage.sh [no-webhook]
#
# PARAMETERS:
#   1. no-webhook: Optional flag to disable webhook notifications and 
#      display the output only in the terminal.
#
# FEATURES:
#   - Disk space monitoring with WARNING and CRITICAL thresholds
#   - Cooldown period to prevent alert fatigue
#   - Logging to /var/log/check-resource-usage.log
#   - Webhook notifications via Slack
#
# FUTURE METRICS (To be implemented):
#   - CPU usage monitoring
#   - Memory (RAM) usage monitoring
#   - Disk I/O monitoring
#   - Network usage monitoring
#   - Load average monitoring
#   - Process count monitoring
#   - Swap usage monitoring
#   - System uptime tracking
#   - Temperature monitoring (if applicable)
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
# Ensure the script is run as root
if [[ $EUID -ne 0 ]]; then
   echo "This script must be run as root (use sudo)."
   exit 1
fi

LOG_FILE="/var/log/check-resource-usage.log"
STATE_FILE="${SCRIPT_DIR}/.check-resource-usage-state"
SEND_WEBHOOK=true

# --- Argument Parsing ---
for arg in "$@"; do
    if [ "$arg" == "no-webhook" ]; then
        SEND_WEBHOOK=false
    fi
done

# --- Logging Function ---
log_message() {
    local message="$1"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $message" | tee -a "$LOG_FILE"
}

# --- Cooldown Management ---
# Check if enough time has passed since the last alert for a specific partition and severity
should_send_alert() {
    local partition="$1"
    local severity="$2"
    local cooldown_minutes="$CHECK_RESOURCE_USAGE_ALERT_COOLDOWN_MINUTES"
    local key="${partition}_${severity}"
    
    # Create state file if it doesn't exist
    touch "$STATE_FILE" 2>/dev/null || true
    
    # Get the last alert timestamp for this partition/severity
    local last_alert_time=$(grep "^${key}=" "$STATE_FILE" 2>/dev/null | cut -d'=' -f2)
    
    if [ -z "$last_alert_time" ]; then
        # No previous alert found, send it
        return 0
    fi
    
    local current_time=$(date +%s)
    local cooldown_seconds=$((cooldown_minutes * 60))
    local time_diff=$((current_time - last_alert_time))
    
    if [ $time_diff -ge $cooldown_seconds ]; then
        # Cooldown period has passed
        return 0
    else
        # Still in cooldown period
        local remaining_minutes=$(( (cooldown_seconds - time_diff) / 60 ))
        log_message "Alert suppressed for ${partition} (${severity}): cooldown active (${remaining_minutes} minutes remaining)"
        return 1
    fi
}

# Record that an alert was sent
record_alert() {
    local partition="$1"
    local severity="$2"
    local key="${partition}_${severity}"
    local current_time=$(date +%s)
    
    # Remove old entry if exists and add new one
    grep -v "^${key}=" "$STATE_FILE" > "${STATE_FILE}.tmp" 2>/dev/null || true
    echo "${key}=${current_time}" >> "${STATE_FILE}.tmp"
    mv "${STATE_FILE}.tmp" "$STATE_FILE"
}

# --- Disk Usage Monitoring ---
check_disk_usage() {
    local partitions="$CHECK_RESOURCE_USAGE_PARTITIONS"
    local warning_threshold="$CHECK_RESOURCE_USAGE_DISK_WARNING_THRESHOLD"
    local critical_threshold="$CHECK_RESOURCE_USAGE_DISK_CRITICAL_THRESHOLD"
    local alerts_sent=0
    local alert_details=""
    
    log_message "Starting disk usage check"
    
    for partition in $partitions; do
        # Get disk usage percentage (without % sign)
        local usage=$(df -h "$partition" 2>/dev/null | awk 'NR==2 {gsub(/%/,"",$5); print $5}')
        
        if [ -z "$usage" ]; then
            log_message "Warning: Could not read usage for partition $partition"
            continue
        fi
        
        log_message "Partition $partition: ${usage}% used"
        
        # Determine severity
        local severity=""
        local color=""
        local emoji=""
        
        if [ "$usage" -ge "$critical_threshold" ]; then
            severity="CRITICAL"
            color="#E01E5A"  # Red
            emoji="🚨"
        elif [ "$usage" -ge "$warning_threshold" ]; then
            severity="WARNING"
            color="#E8A317"  # Amber
            emoji="⚠️"
        else
            # Usage is within acceptable range
            continue
        fi
        
        # Check if we should send an alert (cooldown check)
        if should_send_alert "$partition" "$severity"; then
            log_message "Alert triggered: $partition at ${usage}% ($severity)"
            
            # Get additional disk info
            local disk_info=$(df -h "$partition" | awk 'NR==2 {print "Size: "$2", Used: "$3", Available: "$4}')
            
            alert_details+="\n• *${partition}*: ${usage}% used ($severity)\n   └ ${disk_info}"
            
            # Send individual alert via webhook
            if [ "$SEND_WEBHOOK" = true ]; then
                send_disk_alert "$partition" "$usage" "$severity" "$color" "$emoji" "$disk_info"
            fi
            
            # Record that we sent this alert
            record_alert "$partition" "$severity"
            ((alerts_sent++))
        fi
    done
    
    if [ $alerts_sent -eq 0 ]; then
        log_message "No disk alerts triggered (all partitions within thresholds)"
    else
        log_message "Sent $alerts_sent disk usage alert(s)"
    fi
}

# --- Send Alert via Webhook ---
send_disk_alert() {
    local partition="$1"
    local usage="$2"
    local severity="$3"
    local color="$4"
    local emoji="$5"
    local disk_info="$6"
    
    # Build user mentions
    local mentions=""
    for user in $CHECK_RESOURCE_USAGE_PING_USERS; do
        mentions+="<@$user> "
    done
    
    local title="${severity}: Disk space alert on ${partition}"
    local details="Partition *${partition}* is at *${usage}% capacity*\n${disk_info}"
    
    if [ "$severity" = "CRITICAL" ]; then
        details+="\n\n⚠️ *Immediate action required!*\nAttention: $mentions"
    else
        details+="\n\nAttention: $mentions"
    fi
    
    # Create JSON payload
    local payload=$(cat <<EOF
{
  "text": "$emoji *Resource Alert - $CHECK_RESOURCE_USAGE_SERVER_NAME*",
  "attachments": [
    {
      "color": "$color",
      "title": "$title",
      "text": "$details",
      "footer": "Check executed on: $(date '+%Y-%m-%d %H:%M:%S')"
    }
  ]
}
EOF
)
    
    # Send to webhook
    curl -s -X POST -H 'Content-type: application/json' --data "$payload" "$CHECK_RESOURCE_USAGE_SLACK_WEBHOOK_URL" > /dev/null
    log_message "Webhook notification sent for $partition ($severity)"
}

# =============================================================================
# FUTURE MONITORING FUNCTIONS (To be implemented)
# =============================================================================

# --- CPU Usage Monitoring ---
# check_cpu_usage() {
#     # Use: top, mpstat, or /proc/stat
#     # Monitor: Overall CPU percentage, per-core usage
#     # Thresholds: WARNING at 80%, CRITICAL at 95%
#     # Alert if sustained high usage over time period (e.g., 5 minutes)
#     log_message "CPU monitoring not yet implemented"
# }

# --- Memory Usage Monitoring ---
# check_memory_usage() {
#     # Use: free -m, /proc/meminfo
#     # Monitor: Used RAM percentage, available memory
#     # Thresholds: WARNING at 85%, CRITICAL at 95%
#     # Consider buffers/cache vs actual application memory
#     log_message "Memory monitoring not yet implemented"
# }

# --- Disk I/O Monitoring ---
# check_disk_io() {
#     # Use: iostat, /proc/diskstats
#     # Monitor: Read/write speeds, queue length, I/O wait percentage
#     # Thresholds: Based on baseline performance metrics
#     # Detect sustained high I/O wait times
#     log_message "Disk I/O monitoring not yet implemented"
# }

# --- Network Usage Monitoring ---
# check_network_usage() {
#     # Use: ifstat, /proc/net/dev, vnstat
#     # Monitor: Incoming/outgoing traffic rates
#     # Thresholds: Spike detection, bandwidth saturation
#     # Track per-interface statistics
#     log_message "Network monitoring not yet implemented"
# }

# --- Load Average Monitoring ---
# check_load_average() {
#     # Use: uptime, /proc/loadavg
#     # Monitor: 1, 5, and 15 minute load averages
#     # Thresholds: Relative to number of CPU cores
#     # Alert if load > (cores * threshold_multiplier)
#     log_message "Load average monitoring not yet implemented"
# }

# --- Process Count Monitoring ---
# check_process_count() {
#     # Use: ps, /proc
#     # Monitor: Total running processes, zombie processes
#     # Thresholds: Absolute count or unusual spike detection
#     # Identify process leaks or fork bombs
#     log_message "Process count monitoring not yet implemented"
# }

# --- Swap Usage Monitoring ---
# check_swap_usage() {
#     # Use: free -m, /proc/swaps
#     # Monitor: Swap space usage percentage
#     # Thresholds: WARNING at 50%, CRITICAL at 80%
#     # High swap usage indicates memory pressure
#     log_message "Swap usage monitoring not yet implemented"
# }

# --- System Uptime Tracking ---
# check_system_uptime() {
#     # Use: uptime, /proc/uptime
#     # Monitor: Days since last reboot
#     # Alert: Informational for maintenance planning
#     # No critical thresholds typically needed
#     log_message "Uptime tracking not yet implemented"
# }

# --- Temperature Monitoring ---
# check_temperature() {
#     # Use: sensors (lm-sensors package), /sys/class/thermal
#     # Monitor: CPU temperature, system temperature
#     # Thresholds: WARNING at 75°C, CRITICAL at 85°C
#     # Hardware-specific, may not be available on VMs
#     log_message "Temperature monitoring not yet implemented"
# }

# =============================================================================
# MAIN EXECUTION
# =============================================================================

log_message "========================================="
log_message "Resource usage check started"
log_message "========================================="

# Execute monitoring checks
check_disk_usage

# Future checks (uncomment when implemented):
# check_cpu_usage
# check_memory_usage
# check_disk_io
# check_network_usage
# check_load_average
# check_process_count
# check_swap_usage
# check_system_uptime
# check_temperature

log_message "========================================="
log_message "Resource usage check completed"
log_message "========================================="

# Console output if webhook is disabled
if [ "$SEND_WEBHOOK" = false ]; then
    echo ""
    echo "--- RESOURCE USAGE REPORT ($CHECK_RESOURCE_USAGE_SERVER_NAME) ---"
    echo "Check completed. See $LOG_FILE for details."
    echo "-----------------------------------------------------------"
fi
