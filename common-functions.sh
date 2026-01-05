#!/bin/bash

################################################################################
# COMMON FUNCTIONS FOR SERVER SCRIPTS
#
# This file contains shared utility functions used across multiple
# server management scripts. It should be sourced at the beginning of
# each script, before any other operations.
################################################################################

# =============================================================================
# AUTO-UPDATE FUNCTION
# =============================================================================
# Automatically updates scripts from git repository if enabled in config.
# This function runs silently and never interrupts script execution.
# If git pull fails for any reason, the error is ignored and script continues.
# =============================================================================

auto_update_scripts() {
    # Determine script directory
    local script_dir="$(cd "$(dirname "${BASH_SOURCE[1]}")" && pwd)"
    local config_file="${script_dir}/config.sh"
    
    # Try to load AUTO_UPDATE_SCRIPTS from config.sh if it exists
    local auto_update="true"  # Default value
    
    if [ -f "$config_file" ]; then
        # Source only the AUTO_UPDATE_SCRIPTS variable
        auto_update=$(grep -E "^AUTO_UPDATE_SCRIPTS=" "$config_file" 2>/dev/null | head -1 | cut -d'=' -f2 | tr -d '"' | tr -d "'")
        # If not found or empty, use default
        [ -z "$auto_update" ] && auto_update="true"
    fi
    
    # Only proceed if auto-update is enabled
    if [ "$auto_update" = "true" ]; then
        # Check if we're in a git repository
        if git -C "$script_dir" rev-parse --git-dir > /dev/null 2>&1; then
            # Attempt git pull, suppress all output and ignore errors
            git -C "$script_dir" pull --quiet > /dev/null 2>&1 || true
        fi
    fi
}

# Execute auto-update when this file is sourced
auto_update_scripts
