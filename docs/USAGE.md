# Terminal Session Historian - Usage Guide

This guide covers detailed usage scenarios and configuration options.

## Table of Contents

- [Basic Usage](#basic-usage)
- [Configuration Deep Dive](#configuration-deep-dive)
- [Monitoring Sources](#monitoring-sources)
- [Summarization Options](#summarization-options)
- [LLM Integration](#llm-integration)
- [Systemd Management](#systemd-management)
- [Troubleshooting](#troubleshooting)

---

## Basic Usage

### Running the Monitor

The monitor watches your configured sources and appends new activity to your history file.

```bash
# Run as a daemon (normal operation)
terminal-historian-monitor

# Run in foreground with debug output
terminal-historian-monitor -f

# Single capture pass (for cron jobs)
terminal-historian-monitor --once
```

### Generating Summaries

The summarizer creates a condensed markdown file from your raw history.

```bash
# Generate summary to default location
terminal-historian-summarize

# Output to specific file
terminal-historian-summarize -o ~/my-summary.md

# Print to terminal (useful for piping)
terminal-historian-summarize --stdout

# Verbose output
terminal-historian-summarize -v
```

---

## Configuration Deep Dive

Config location: `~/.config/terminal-historian/config`

### Storage Paths

```bash
# Primary history file (append-only, never truncated)
RAW_HISTORY_PATH="$HOME/.local/share/terminal-historian/raw_history.txt"

# Generated summary file
SUMMARY_PATH="$HOME/.local/share/terminal-historian/context_summary.md"

# Daily session logs directory
SESSION_LOG_DIR="$HOME/.local/share/terminal-historian/sessions"
```

### Source Configuration

```bash
# Primary shell history (leave empty for auto-detection)
SHELL_ACTIVITY_SOURCE=""

# Additional directories to monitor
# Space-separated list of paths
ADDITIONAL_LOG_DIRS="/var/log/myapp $HOME/.config/myapp/logs"
```

Auto-detection checks these locations in order:
1. `~/.bash_history`
2. `~/.zsh_history`
3. `~/.local/share/fish/fish_history`
4. `$HISTFILE` environment variable

### Timing Configuration

```bash
# How often to check for new content (seconds)
CHECK_INTERVAL=60

# How often to regenerate summary (days)
SUMMARY_INTERVAL=7

# Maximum age of sessions to include in summary (days)
MAX_SESSION_AGE=30
```

### Summary Options

```bash
# Maximum lines in generated summary
MAX_SUMMARY_LINES=500

# Include working directories in summary
INCLUDE_DIRECTORIES=true

# Include file paths in summary
INCLUDE_FILES=true

# Include command statistics in summary
INCLUDE_COMMANDS=true
```

---

## Monitoring Sources

### Shell History

The most common source is your shell's history file. The monitor tracks file size and captures new content as it's appended.

**Bash**: `~/.bash_history`
- Ensure `HISTFILE` is set
- Consider increasing `HISTSIZE` and `HISTFILESIZE`

**Zsh**: `~/.zsh_history`
- Works with both standard and extended history formats

**Fish**: `~/.local/share/fish/fish_history`
- Uses fish's native history format

### Custom Log Directories

Monitor application-specific logs by adding them to `ADDITIONAL_LOG_DIRS`:

```bash
ADDITIONAL_LOG_DIRS="/var/log/myapp $HOME/projects/myapp/logs"
```

The monitor will find files matching:
- `*.log`
- `*.jsonl`
- `*history*`

Files modified within the last 60 minutes are processed.

---

## Summarization Options

### What Gets Summarized

1. **Working Directories** - Extracted from `cd` commands and path references
2. **Files Accessed** - Files opened with editors, cat, etc.
3. **Command Patterns** - Statistics on common tool usage (git, docker, etc.)
4. **Recent Activity** - Last N lines of raw history

### Summary Structure

```markdown
# Terminal Session Context Summary

## Working Directories
- `/home/user/projects/myapp`
- `/etc/nginx`

## Files Accessed
/home/user/projects/myapp/src/main.py
/etc/nginx/nginx.conf

## Command Patterns
- **git**: 45 occurrences
- **docker**: 23 occurrences

## Recent Activity
[last 50 entries from history]

---
_Generated: 2025-01-15 10:30:00_
```

---

## LLM Integration

Enable LLM-powered summarization for more intelligent context extraction.

### Configuration

```bash
# Enable LLM summarization
LLM_SUMMARIZATION=true

# Command to invoke your LLM
LLM_COMMAND="ollama run llama2"
```

### Supported LLM Backends

**Ollama (local)**
```bash
LLM_COMMAND="ollama run llama2"
```

**LM Studio (local)**
```bash
LLM_COMMAND="curl -s http://localhost:1234/v1/completions -d @-"
```

**Custom script**
```bash
LLM_COMMAND="/path/to/my-llm-wrapper.sh"
```

The summarizer pipes the prompt to stdin of your command and captures stdout.

---

## Systemd Management

### Service Commands

```bash
# Start the service
systemctl --user start terminal-historian

# Stop the service
systemctl --user stop terminal-historian

# Restart after config changes
systemctl --user restart terminal-historian

# Enable on login
systemctl --user enable terminal-historian

# Disable auto-start
systemctl --user disable terminal-historian

# Check status
systemctl --user status terminal-historian
```

### Viewing Logs

```bash
# Follow live logs
journalctl --user -u terminal-historian -f

# Last 100 lines
journalctl --user -u terminal-historian -n 100

# Logs from today
journalctl --user -u terminal-historian --since today
```

### Service File Location

`~/.config/systemd/user/terminal-historian.service`

After modifying the service file:
```bash
systemctl --user daemon-reload
systemctl --user restart terminal-historian
```

---

## Troubleshooting

### Monitor Not Capturing

1. **Check source detection**
   ```bash
   terminal-historian-monitor -f
   # Look for "Monitoring N source(s)" message
   ```

2. **Verify file permissions**
   ```bash
   ls -la ~/.bash_history  # or your shell's history
   ```

3. **Check data directory**
   ```bash
   ls -la ~/.local/share/terminal-historian/
   ```

### Empty Summary

1. **Verify raw history has content**
   ```bash
   wc -l ~/.local/share/terminal-historian/raw_history.txt
   ```

2. **Run summarizer manually**
   ```bash
   terminal-historian-summarize -v
   ```

### Service Won't Start

1. **Check for errors**
   ```bash
   journalctl --user -u terminal-historian -n 50
   ```

2. **Verify script permissions**
   ```bash
   ls -la ~/.local/bin/terminal-historian-*
   ```

3. **Test manual execution**
   ```bash
   ~/.local/bin/terminal-historian-monitor -f
   ```

### High CPU Usage

Increase `CHECK_INTERVAL` in your config:
```bash
CHECK_INTERVAL=300  # Check every 5 minutes instead of 60 seconds
```

---

## Tips and Tricks

### Backup Your History

```bash
# Create dated backup
cp ~/.local/share/terminal-historian/raw_history.txt \
   ~/backups/terminal-history-$(date +%Y%m%d).txt
```

### Search History

```bash
# Search for specific commands
grep "docker" ~/.local/share/terminal-historian/raw_history.txt

# Search with context
grep -C 3 "error" ~/.local/share/terminal-historian/raw_history.txt
```

### Rotate Large History Files

If your history gets too large:
```bash
# Keep last 100,000 lines
tail -n 100000 ~/.local/share/terminal-historian/raw_history.txt > /tmp/history.tmp
mv /tmp/history.tmp ~/.local/share/terminal-historian/raw_history.txt
```

### Quick Context for LLMs

```bash
# Copy recent summary to clipboard (Linux)
terminal-historian-summarize --stdout | xclip -selection clipboard

# Copy recent summary to clipboard (macOS)
terminal-historian-summarize --stdout | pbcopy
```
