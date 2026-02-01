#!/usr/bin/env bash
# Terminal Session Historian - Utility Functions
# Source this file in other scripts: source "$(dirname "$0")/utils.sh"

set -euo pipefail

# ============================================================================
# CONFIGURATION
# ============================================================================

CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/terminal-historian"
DATA_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/terminal-historian"
CONFIG_FILE="${HISTORIAN_CONFIG:-$CONFIG_DIR/config}"

# Default values (overridden by config)
RAW_HISTORY_PATH="$DATA_DIR/raw_history.txt"
SUMMARY_PATH="$DATA_DIR/context_summary.md"
SESSION_LOG_DIR="$DATA_DIR/sessions"
SHELL_ACTIVITY_SOURCE=""
ADDITIONAL_LOG_DIRS=""
CHECK_INTERVAL=60
SUMMARY_INTERVAL=7
MAX_SESSION_AGE=30
MAX_SUMMARY_LINES=500
MAX_RAW_HISTORY_BYTES=104857600  # 100MB default (set to 0 to disable)
INCLUDE_DIRECTORIES=true
INCLUDE_FILES=true
INCLUDE_COMMANDS=true
LLM_SUMMARIZATION=false
LLM_COMMAND=""
LOG_LEVEL="INFO"
LOG_FILE="$DATA_DIR/historian.log"

# ============================================================================
# LOGGING
# ============================================================================

declare -A LOG_LEVELS=([DEBUG]=0 [INFO]=1 [WARN]=2 [ERROR]=3)

log() {
    local level="$1"
    shift
    local message="$*"
    local timestamp
    timestamp=$(date '+%Y-%m-%d %H:%M:%S')

    # Check if we should log this level
    local current_level="${LOG_LEVELS[$LOG_LEVEL]:-1}"
    local msg_level="${LOG_LEVELS[$level]:-1}"

    if [[ $msg_level -ge $current_level ]]; then
        local output="[$timestamp] [$level] $message"
        echo "$output" >&2

        # Also write to log file if configured
        if [[ -n "${LOG_FILE:-}" && -d "$(dirname "$LOG_FILE")" ]]; then
            echo "$output" >> "$LOG_FILE"
        fi
    fi
}

log_debug() { log "DEBUG" "$@"; }
log_info() { log "INFO" "$@"; }
log_warn() { log "WARN" "$@"; }
log_error() { log "ERROR" "$@"; }

# ============================================================================
# CONFIGURATION LOADING
# ============================================================================

load_config() {
    if [[ -f "$CONFIG_FILE" ]]; then
        log_debug "Loading config from $CONFIG_FILE"
        # shellcheck source=/dev/null
        source "$CONFIG_FILE"
    else
        log_warn "Config file not found: $CONFIG_FILE (using defaults)"
    fi
}

# ============================================================================
# SHELL HISTORY DETECTION
# ============================================================================

detect_shell_history() {
    # Return configured path if set
    if [[ -n "${SHELL_ACTIVITY_SOURCE:-}" ]]; then
        echo "$SHELL_ACTIVITY_SOURCE"
        return 0
    fi

    # Try common shell history locations
    local locations=(
        "$HOME/.bash_history"
        "$HOME/.zsh_history"
        "$HOME/.local/share/fish/fish_history"
        "$HOME/.history"
        "$HOME/.sh_history"
    )

    for loc in "${locations[@]}"; do
        if [[ -f "$loc" ]]; then
            log_debug "Found shell history at: $loc"
            echo "$loc"
            return 0
        fi
    done

    # Try to detect from current shell
    if [[ -n "${HISTFILE:-}" && -f "$HISTFILE" ]]; then
        log_debug "Found shell history from HISTFILE: $HISTFILE"
        echo "$HISTFILE"
        return 0
    fi

    log_warn "Could not detect shell history location"
    return 1
}

get_log_sources() {
    local sources=()

    # Primary shell history
    local shell_hist
    if shell_hist=$(detect_shell_history); then
        sources+=("$shell_hist")
    fi

    # Additional configured directories
    if [[ -n "${ADDITIONAL_LOG_DIRS:-}" ]]; then
        for dir in $ADDITIONAL_LOG_DIRS; do
            if [[ -d "$dir" ]]; then
                sources+=("$dir")
            fi
        done
    fi

    printf '%s\n' "${sources[@]}"
}

# ============================================================================
# DIRECTORY MANAGEMENT
# ============================================================================

ensure_directories() {
    local dirs=(
        "$CONFIG_DIR"
        "$DATA_DIR"
        "$(dirname "$RAW_HISTORY_PATH")"
        "$(dirname "$SUMMARY_PATH")"
    )

    if [[ -n "${SESSION_LOG_DIR:-}" ]]; then
        dirs+=("$SESSION_LOG_DIR")
    fi

    if [[ -n "${LOG_FILE:-}" ]]; then
        dirs+=("$(dirname "$LOG_FILE")")
    fi

    for dir in "${dirs[@]}"; do
        if [[ ! -d "$dir" ]]; then
            log_debug "Creating directory: $dir"
            mkdir -p "$dir"
        fi
    done
}

# ============================================================================
# FILE OPERATIONS
# ============================================================================

get_file_size_bytes() {
    local file="$1"
    if [[ ! -f "$file" ]]; then
        echo "0"
        return
    fi
    if stat --version &>/dev/null; then
        stat -c %s "$file" 2>/dev/null || echo "0"
    else
        stat -f %z "$file" 2>/dev/null || echo "0"
    fi
}

rotate_raw_history_if_needed() {
    # Skip if max size is 0 (disabled)
    if [[ "${MAX_RAW_HISTORY_BYTES:-0}" -eq 0 ]]; then
        return 0
    fi

    local current_size
    current_size=$(get_file_size_bytes "$RAW_HISTORY_PATH")

    if [[ $current_size -gt $MAX_RAW_HISTORY_BYTES ]]; then
        log_info "Raw history exceeds limit ($(numfmt --to=iec $current_size) > $(numfmt --to=iec $MAX_RAW_HISTORY_BYTES)), rotating..."

        # Keep the most recent 75% of max size
        local keep_bytes=$(( MAX_RAW_HISTORY_BYTES * 3 / 4 ))
        local temp_file="${RAW_HISTORY_PATH}.rotating"

        # Use tail -c to keep the last N bytes, then find first complete entry
        tail -c "$keep_bytes" "$RAW_HISTORY_PATH" > "$temp_file"

        # Find first complete entry marker (--- [) and trim incomplete data before it
        local first_marker
        first_marker=$(grep -n -m 1 '^--- \[' "$temp_file" | cut -d: -f1)

        if [[ -n "$first_marker" && "$first_marker" -gt 1 ]]; then
            # Remove incomplete first entry
            tail -n +$first_marker "$temp_file" > "${temp_file}.clean"
            mv "${temp_file}.clean" "$temp_file"
        fi

        # Replace original with rotated version
        mv "$temp_file" "$RAW_HISTORY_PATH"

        local new_size
        new_size=$(get_file_size_bytes "$RAW_HISTORY_PATH")
        log_info "Rotation complete. New size: $(numfmt --to=iec $new_size)"
    fi
}

append_to_history() {
    local content="$1"
    local timestamp
    timestamp=$(date '+%Y-%m-%d %H:%M:%S')

    echo "[$timestamp] $content" >> "$RAW_HISTORY_PATH"
    log_debug "Appended to history: ${content:0:50}..."
}

get_session_file() {
    local date_str
    date_str=$(date '+%Y%m%d')
    echo "$SESSION_LOG_DIR/session_$date_str.log"
}

# ============================================================================
# TIMESTAMP UTILITIES
# ============================================================================

days_since_file_modified() {
    local file="$1"

    if [[ ! -f "$file" ]]; then
        echo "999999"
        return
    fi

    local file_time
    local now

    # Cross-platform stat
    if stat --version &>/dev/null; then
        # GNU stat (Linux)
        file_time=$(stat -c %Y "$file")
    else
        # BSD stat (macOS)
        file_time=$(stat -f %m "$file")
    fi

    now=$(date +%s)
    echo $(( (now - file_time) / 86400 ))
}

# ============================================================================
# TEXT PROCESSING
# ============================================================================

truncate_to_lines() {
    local file="$1"
    local max_lines="$2"

    if [[ -f "$file" ]]; then
        tail -n "$max_lines" "$file"
    fi
}

extract_directories() {
    local file="$1"
    grep -oE '(cd |Working directory: |pwd: )[^";\n]+' "$file" 2>/dev/null | \
        sed 's/^cd //' | sed 's/Working directory: //' | sed 's/pwd: //' | \
        sort -u || true
}

extract_files() {
    local file="$1"
    grep -oE '(vim |nano |cat |less |edit |read |write ).?[^";\n|>]+' "$file" 2>/dev/null | \
        sed 's/^[a-z]* //' | \
        grep -E '^[/~]' | \
        sort -u | \
        head -100 || true
}

extract_commands() {
    local file="$1"
    # Extract command-like patterns
    grep -oE '^\$ .+|^> .+|^\[.*\] .+' "$file" 2>/dev/null | \
        sed 's/^\$ //' | sed 's/^> //' | sed 's/^\[.*\] //' | \
        head -200 || true
}

# ============================================================================
# INITIALIZATION
# ============================================================================

init_historian() {
    load_config
    ensure_directories
}
