#!/usr/bin/env bash
# Terminal Session Historian - Context Summarizer
# Generates condensed context from raw history

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/utils.sh"

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

    local recent_content
    recent_content=$(tail -n 500 "$history_file" 2>/dev/null)

    if [[ -n "$recent_content" ]]; then
        local prompt="Summarize the following terminal session history in 5-10 bullet points. Focus on: main tasks accomplished, tools used, and key decisions made.\n\n$recent_content"

        local summary
        if summary=$(echo "$prompt" | eval "$LLM_COMMAND" 2>/dev/null); then
            echo "$summary"
        else
            echo "_LLM summarization failed_"
        fi
    else
        echo "_Not enough content for LLM summary_"
    fi

    echo ""
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

    echo "_Config: $CONFIG_FILE_"
}

# ============================================================================
# MAIN SUMMARIZATION
# ============================================================================

generate_summary() {
    local output_file="$SUMMARY_PATH"
    local temp_file
    temp_file=$(mktemp)

    log_info "Generating context summary..."

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
