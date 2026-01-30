#!/usr/bin/env bash
# Terminal Session Historian - Context Summarizer
# Generates condensed context from raw history using incremental pending buffer approach

set -euo pipefail

# Resolve symlinks to find actual script location
SCRIPT_PATH="$(readlink -f "${BASH_SOURCE[0]}" 2>/dev/null || realpath "${BASH_SOURCE[0]}" 2>/dev/null || echo "${BASH_SOURCE[0]}")"
SCRIPT_DIR="$(cd "$(dirname "$SCRIPT_PATH")" && pwd)"
source "$SCRIPT_DIR/utils.sh"

# ============================================================================
# PENDING BUFFER STATE MANAGEMENT
# ============================================================================

# These variables are set dynamically after config loads in init_state_tracking()
STATE_DIR=""
LAST_POSITION_FILE=""
ROLLING_SUMMARY_FILE=""

init_state_tracking() {
    # Called after init_historian loads config
    STATE_DIR="${STATE_DIR:-$HOME/.local/state/terminal-historian}"
    LAST_POSITION_FILE="$STATE_DIR/last_summarized_position"
    # Use config path if set, otherwise derive from SUMMARY_PATH
    ROLLING_SUMMARY_FILE="${ROLLING_SUMMARY_PATH:-${SUMMARY_PATH%.md}_rolling.md}"
}

ensure_state_dir() {
    mkdir -p "$STATE_DIR"
}

get_last_position() {
    if [[ -f "$LAST_POSITION_FILE" ]]; then
        cat "$LAST_POSITION_FILE"
    else
        echo "0"
    fi
}

save_last_position() {
    local position="$1"
    echo "$position" > "$LAST_POSITION_FILE"
}

get_file_size() {
    local file="$1"
    if [[ -f "$file" ]]; then
        if stat --version &>/dev/null; then
            stat -c %s "$file" 2>/dev/null || echo "0"
        else
            stat -f %z "$file" 2>/dev/null || echo "0"
        fi
    else
        echo "0"
    fi
}

get_pending_content() {
    local history_file="$1"
    local last_pos
    last_pos=$(get_last_position)
    local current_size
    current_size=$(get_file_size "$history_file")

    if [[ $current_size -gt $last_pos ]]; then
        # Extract only new content since last summary
        tail -c +$((last_pos + 1)) "$history_file" 2>/dev/null
    else
        echo ""
    fi
}

# ============================================================================
# SUMMARIZATION FUNCTIONS
# ============================================================================

generate_header() {
    cat << 'EOF'
# Terminal Session Context Summary

This document contains summarized context from your terminal session history.
Useful for recovering context, documentation, and feeding to LLMs.

---

EOF
}

extract_directory_summary() {
    local history_file="$1"

    if [[ "$INCLUDE_DIRECTORIES" != "true" ]]; then
        return
    fi

    echo "## Working Directories"
    echo ""

    local directories
    directories=$(extract_directories "$history_file")

    if [[ -n "$directories" ]]; then
        echo "$directories" | head -20 | while read -r dir; do
            [[ -n "$dir" ]] && echo "- \`$dir\`"
        done
        local total
        total=$(echo "$directories" | wc -l)
        if [[ $total -gt 20 ]]; then
            echo "- _...and $((total - 20)) more_"
        fi
    else
        echo "_No directories detected_"
    fi

    echo ""
}

extract_file_summary() {
    local history_file="$1"

    if [[ "$INCLUDE_FILES" != "true" ]]; then
        return
    fi

    echo "## Files Accessed"
    echo ""

    local files
    files=$(extract_files "$history_file")

    if [[ -n "$files" ]]; then
        echo '```'
        echo "$files" | head -50
        local total
        total=$(echo "$files" | wc -l)
        if [[ $total -gt 50 ]]; then
            echo "... and $((total - 50)) more files"
        fi
        echo '```'
    else
        echo "_No file access detected_"
    fi

    echo ""
}

extract_command_summary() {
    local history_file="$1"

    if [[ "$INCLUDE_COMMANDS" != "true" ]]; then
        return
    fi

    echo "## Command Patterns"
    echo ""

    # Extract common command prefixes
    local patterns=(
        "git:git"
        "package managers:npm\|yarn\|pnpm\|pip\|cargo\|apt\|brew"
        "containers:docker\|podman\|kubectl"
        "remote:ssh\|scp\|rsync"
        "services:systemctl\|service"
        "editors:vim\|nvim\|nano\|code"
    )

    local found_any=false
    for pattern in "${patterns[@]}"; do
        local name="${pattern%%:*}"
        local regex="${pattern##*:}"
        local count
        count=$(grep -ciE "$regex" "$history_file" 2>/dev/null) || count=0
        if [[ $count -gt 0 ]]; then
            echo "- **$name**: $count occurrences"
            found_any=true
        fi
    done

    if [[ "$found_any" == "false" ]]; then
        echo "_No common command patterns detected_"
    fi

    echo ""
}

extract_recent_activity() {
    local history_file="$1"

    echo "## Recent Activity"
    echo ""

    if [[ -f "$history_file" ]]; then
        local lines
        lines=$(wc -l < "$history_file")

        echo "_Total history: $lines lines_"
        echo ""
        echo "### Last 50 Entries"
        echo ""
        echo '```'
        tail -n 100 "$history_file" | \
            grep -vE '^\s*$' | \
            tail -50
        echo '```'
    else
        echo "_No history file found_"
    fi

    echo ""
}

generate_llm_summary() {
    local history_file="$1"

    if [[ "$LLM_SUMMARIZATION" != "true" || -z "${LLM_COMMAND:-}" ]]; then
        return
    fi

    echo "## LLM-Generated Summary"
    echo ""
    echo "_See rolling summary file for incremental summaries_"
    echo ""
}

# Incremental LLM summarization - only processes new content since last run
generate_incremental_llm_summary() {
    local history_file="$1"

    if [[ "$LLM_SUMMARIZATION" != "true" || -z "${LLM_COMMAND:-}" ]]; then
        log_info "LLM summarization disabled or not configured"
        return 0
    fi

    ensure_state_dir

    local pending_content
    pending_content=$(get_pending_content "$history_file")
    local pending_lines
    pending_lines=$(echo "$pending_content" | wc -l)

    if [[ -z "$pending_content" || "$pending_lines" -lt 10 ]]; then
        log_info "No significant new content to summarize (${pending_lines} lines)"
        return 0
    fi

    log_info "Found $pending_lines new lines to summarize"

    # Escape the content for JSON - handle newlines, quotes, backslashes
    local escaped_content
    escaped_content=$(echo "$pending_content" | \
        sed 's/\\/\\\\/g' | \
        sed 's/"/\\"/g' | \
        sed ':a;N;$!ba;s/\n/\\n/g' | \
        head -c 50000)  # Limit to ~50KB to stay within token limits

    local prompt="Summarize the following terminal/Claude session activity in 3-7 concise bullet points. Focus on: main tasks worked on, key decisions made, problems solved, and current project state. Be specific about file paths, commands, and outcomes.

Activity since last summary:
$escaped_content"

    log_info "Sending to Claude API for summarization..."

    # Get API key
    local api_key
    api_key=$(cat ~/.config/terminal-historian/api_key 2>/dev/null || echo "${ANTHROPIC_API_KEY:-}")

    if [[ -z "$api_key" ]]; then
        log_error "No API key found. Set ANTHROPIC_API_KEY or create ~/.config/terminal-historian/api_key"
        return 1
    fi

    # Make API call
    local response
    response=$(curl -s https://api.anthropic.com/v1/messages \
        -H "Content-Type: application/json" \
        -H "x-api-key: $api_key" \
        -H "anthropic-version: 2023-06-01" \
        -d "{
            \"model\": \"${CLAUDE_MODEL:-claude-3-haiku-20240307}\",
            \"max_tokens\": 1024,
            \"messages\": [{
                \"role\": \"user\",
                \"content\": $(echo "$prompt" | jq -Rs .)
            }]
        }" 2>/dev/null)

    # Check for errors
    if echo "$response" | jq -e '.error' &>/dev/null; then
        local error_msg
        error_msg=$(echo "$response" | jq -r '.error.message // .error.type // "Unknown error"')
        log_error "Claude API error: $error_msg"
        return 1
    fi

    local summary
    summary=$(echo "$response" | jq -r '.content[0].text // empty')

    if [[ -z "$summary" ]]; then
        log_error "No summary returned from API"
        log_debug "Response: $response"
        return 1
    fi

    # Append to rolling summary file
    {
        echo ""
        echo "---"
        echo "### $(date '+%Y-%m-%d %H:%M:%S')"
        echo "_Summarized $pending_lines lines of new activity_"
        echo ""
        echo "$summary"
    } >> "$ROLLING_SUMMARY_FILE"

    # Update position marker
    local current_size
    current_size=$(get_file_size "$history_file")
    save_last_position "$current_size"

    log_info "Summary appended to: $ROLLING_SUMMARY_FILE"
    log_info "Position updated to: $current_size bytes"

    return 0
}

generate_footer() {
    local history_file="$1"

    echo "---"
    echo ""
    echo "_Generated: $(date '+%Y-%m-%d %H:%M:%S')_  "

    if [[ -f "$history_file" ]]; then
        local lines size
        lines=$(wc -l < "$history_file")
        size=$(du -h "$history_file" | cut -f1)
        echo "_Source: $lines lines ($size)_  "
    fi

    echo "_Config: ${CONFIG_FILE}_"
}

# ============================================================================
# MAIN SUMMARIZATION
# ============================================================================

ensure_rolling_summary_header() {
    if [[ ! -f "$ROLLING_SUMMARY_FILE" ]]; then
        cat > "$ROLLING_SUMMARY_FILE" << 'EOF'
# Terminal Session History - Rolling Summary

This file contains incremental AI-generated summaries of your terminal and Claude Code sessions.
Each section represents a summary of activity since the previous summary.

Use this for: context recovery, documentation, feeding to LLMs, interview prep notes.

EOF
        log_info "Created rolling summary file: $ROLLING_SUMMARY_FILE"
    fi
}

generate_summary() {
    # Initialize state tracking paths now that config is loaded
    init_state_tracking

    local output_file="$SUMMARY_PATH"
    local temp_file
    temp_file=$(mktemp)

    log_info "Generating context summary..."
    log_debug "Rolling summary file: $ROLLING_SUMMARY_FILE"

    ensure_state_dir
    ensure_rolling_summary_header

    # First, run incremental LLM summarization (appends to rolling file)
    if [[ -f "$RAW_HISTORY_PATH" ]]; then
        generate_incremental_llm_summary "$RAW_HISTORY_PATH" || true
    fi

    # Then generate the static summary file (for quick reference)
    {
        generate_header

        if [[ -f "$RAW_HISTORY_PATH" ]]; then
            extract_directory_summary "$RAW_HISTORY_PATH"
            extract_file_summary "$RAW_HISTORY_PATH"
            extract_command_summary "$RAW_HISTORY_PATH"
            generate_llm_summary "$RAW_HISTORY_PATH"
            extract_recent_activity "$RAW_HISTORY_PATH"
        else
            echo "_No history available yet. Run the monitor to start collecting._"
            echo ""
        fi

        generate_footer "$RAW_HISTORY_PATH"
    } > "$temp_file"

    # Truncate if needed
    local line_count
    line_count=$(wc -l < "$temp_file")
    if [[ $line_count -gt $MAX_SUMMARY_LINES ]]; then
        head -n "$MAX_SUMMARY_LINES" "$temp_file" > "${temp_file}.truncated"
        mv "${temp_file}.truncated" "$temp_file"
        echo "" >> "$temp_file"
        echo "_[Truncated to $MAX_SUMMARY_LINES lines]_" >> "$temp_file"
    fi

    mv "$temp_file" "$output_file"
    log_info "Summary written to: $output_file"
    log_info "Summary size: $(wc -l < "$output_file") lines"
}

# ============================================================================
# CLI INTERFACE
# ============================================================================

show_help() {
    cat << EOF
Terminal Session Historian - Context Summarizer

Generates a condensed summary of your terminal session history,
optimized for quick reference or feeding to LLMs.

Usage: $(basename "$0") [OPTIONS]

Options:
    -h, --help      Show this help message
    -o, --output    Specify output file (default: from config)
    -v, --verbose   Enable verbose output
    --stdout        Print summary to stdout instead of file

Examples:
    $(basename "$0")                  # Generate summary to default location
    $(basename "$0") -o summary.md    # Output to specific file
    $(basename "$0") --stdout         # Print to terminal
EOF
}

main() {
    init_historian

    local to_stdout=false

    while [[ $# -gt 0 ]]; do
        case "$1" in
            -h|--help)
                show_help
                exit 0
                ;;
            -o|--output)
                SUMMARY_PATH="$2"
                shift 2
                ;;
            -v|--verbose)
                LOG_LEVEL="DEBUG"
                shift
                ;;
            --stdout)
                to_stdout=true
                shift
                ;;
            *)
                log_error "Unknown option: $1"
                show_help
                exit 1
                ;;
        esac
    done

    if $to_stdout; then
        SUMMARY_PATH="/dev/stdout"
        LOG_LEVEL="ERROR"  # Suppress log output when printing to stdout
    fi

    generate_summary
}

# Run if executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
