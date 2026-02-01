#!/usr/bin/env bash
# One-time rotation script to immediately reduce raw_history.txt to configured limit
# Run this once to fix the 44GB file, then let monitor.sh handle ongoing rotation

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/utils.sh"

init_historian

echo "Current raw_history.txt size: $(du -h "$RAW_HISTORY_PATH" | cut -f1)"
echo "Configured max size: $(numfmt --to=iec $MAX_RAW_HISTORY_BYTES)"
echo ""

if [[ $(get_file_size_bytes "$RAW_HISTORY_PATH") -gt $MAX_RAW_HISTORY_BYTES ]]; then
    echo "File exceeds limit, rotating now..."
    echo ""
    rotate_raw_history_if_needed
    echo ""
    echo "Final size: $(du -h "$RAW_HISTORY_PATH" | cut -f1)"
else
    echo "File is already within limits, no rotation needed."
fi
