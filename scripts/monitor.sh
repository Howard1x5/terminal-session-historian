#!/usr/bin/env bash
# Terminal Session Historian - Activity Monitor
# Watches terminal/shell activity and appends to raw history

set -euo pipefail

# Resolve symlinks to find actual script location
SCRIPT_PATH="$(readlink -f "${BASH_SOURCE[0]}" 2>/dev/null || realpath "${BASH_SOURCE[0]}" 2>/dev/null || echo "${BASH_SOURCE[0]}")"
SCRIPT_DIR="$(cd "$(dirname "$SCRIPT_PATH")" && pwd)"
source "$SCRIPT_DIR/utils.sh"

# ============================================================================
# MONITOR STATE
# ============================================================================

declare -A LAST_POSITIONS
RUNNING=true

# ============================================================================
# SIGNAL HANDLING
# ============================================================================

cleanup() {
    log_info "Shutting down monitor..."
    RUNNING=false
}

trap cleanup SIGTERM SIGINT SIGHUP

# ============================================================================
# MONITORING FUNCTIONS
# ============================================================================

get_file_size() {
    local file="$1"
    if stat --version &>/dev/null; then
        stat -c %s "$file" 2>/dev/null || echo "0"
    else
        stat -f %z "$file" 2>/dev/null || echo "0"
    fi
}

process_source() {
    local source="$1"

    # Handle directories - find log files within
    if [[ -d "$source" ]]; then
        find "$source" -type f \( -name "*.log" -o -name "*.jsonl" -o -name "*history*" \) \
            -mmin -60 2>/dev/null | while read -r file; do
            process_file "$file"
        done
    elif [[ -f "$source" ]]; then
        process_file "$source"
    fi
}

process_file() {
    local file="$1"
    local current_size
    current_size=$(get_file_size "$file")

    # Get last known position for this file
    local last_pos="${LAST_POSITIONS[$file]:-0}"

    # Check for new content
    if [[ $current_size -gt $last_pos ]]; then
        local new_content
        new_content=$(tail -c +$((last_pos + 1)) "$file" 2>/dev/null) || return

        if [[ -n "$new_content" ]]; then
            process_content "$new_content" "$file"
            LAST_POSITIONS[$file]=$current_size
        fi
    fi
}

process_content() {
    local content="$1"
    local source_file="$2"

    # Add source marker
    local source_name
    source_name=$(basename "$source_file")

    # Append to raw history with source info
    {
        echo "--- [$source_name] $(date '+%Y-%m-%d %H:%M:%S') ---"
        echo "$content"
    } >> "$RAW_HISTORY_PATH"

    # Also append to daily session log if enabled
    if [[ -n "${SESSION_LOG_DIR:-}" ]]; then
        local session_file
        session_file=$(get_session_file)
        {
            echo "--- [$source_name] $(date '+%Y-%m-%d %H:%M:%S') ---"
            echo "$content"
        } >> "$session_file"
    fi

    log_debug "Captured $(echo "$content" | wc -l) lines from $source_name"
}

check_summary_needed() {
    local days_since
    days_since=$(days_since_file_modified "$SUMMARY_PATH")

    if [[ $days_since -ge $SUMMARY_INTERVAL ]]; then
        log_info "Summary is $days_since days old, regenerating..."
        "$SCRIPT_DIR/summarizer.sh"
    fi
}

# ============================================================================
# MAIN LOOP
# ============================================================================

main() {
    init_historian

    log_info "Terminal Session Historian monitor starting..."
    log_info "Raw history: $RAW_HISTORY_PATH"
    log_info "Check interval: ${CHECK_INTERVAL}s"

    # Get configured sources
    local sources
    mapfile -t sources < <(get_log_sources)

    if [[ ${#sources[@]} -eq 0 ]]; then
        log_error "No log sources found. Configure SHELL_ACTIVITY_SOURCE in your config."
        exit 1
    fi

    log_info "Monitoring ${#sources[@]} source(s)"
    for src in "${sources[@]}"; do
        log_info "  - $src"
    done

    local check_count=0
    local summary_check_interval=100  # Check summary every N iterations
    local rotation_check_interval=10  # Check rotation every N iterations

    while $RUNNING; do
        # Process all configured sources
        for source in "${sources[@]}"; do
            process_source "$source"
        done

        ((check_count++)) || true

        # Check if raw history needs rotation (every ~10 minutes at default interval)
        if [[ $((check_count % rotation_check_interval)) -eq 0 ]]; then
            rotate_raw_history_if_needed
        fi

        # Periodically check if summary needs regeneration
        if [[ $((check_count % summary_check_interval)) -eq 0 ]]; then
            check_summary_needed
        fi

        sleep "$CHECK_INTERVAL"
    done

    log_info "Monitor stopped"
}

# ============================================================================
# CLI INTERFACE
# ============================================================================

show_help() {
    cat << EOF
Terminal Session Historian - Activity Monitor

Usage: $(basename "$0") [OPTIONS]

Options:
    -h, --help      Show this help message
    -f, --foreground   Run in foreground with verbose output
    -1, --once      Run once and exit (useful for cron)

Examples:
    $(basename "$0")              # Start monitoring daemon
    $(basename "$0") --once       # Single capture pass
    $(basename "$0") -f           # Foreground with debug output
EOF
}

# Run if executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    RUN_ONCE=false

    while [[ $# -gt 0 ]]; do
        case "$1" in
            -h|--help)
                show_help
                exit 0
                ;;
            -f|--foreground)
                LOG_LEVEL="DEBUG"
                shift
                ;;
            -1|--once)
                RUN_ONCE=true
                shift
                ;;
            *)
                log_error "Unknown option: $1"
                show_help
                exit 1
                ;;
        esac
    done

    if $RUN_ONCE; then
        init_historian
        mapfile -t sources < <(get_log_sources)
        for source in "${sources[@]}"; do
            process_source "$source"
        done
        log_info "Single capture pass complete"
    else
        main
    fi
fi
