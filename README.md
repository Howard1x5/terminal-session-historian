# Terminal Session Historian

A lightweight automation that backs up your terminal session activity into a searchable text archive with optional LLM-powered summarization for efficient context retrieval.

## Why?

Ever tried to remember what you did three weeks ago when setting up that server? Or needed to document a complex procedure you figured out through trial and error? Or wanted to quickly give an LLM context about your recent work?

Terminal Session Historian solves these problems by:

- **Continuously archiving** your shell activity to a rolling history file
- **Generating summaries** optimized for quick scanning or LLM consumption
- **Running silently** in the background via systemd
- **Keeping everything local** - your data never leaves your machine

## Features

- Monitors shell history and custom log sources
- **Monitors AI coding agents** (Claude Code, Cursor, etc.) for session tracking
- Append-only raw history (never loses data)
- **Incremental LLM summarization** via Claude API (token-efficient pending buffer approach)
- **Rolling summary file** that accumulates context over time
- Daily session logs for granular access
- Systemd integration for hands-off operation
- Cross-platform (Linux, macOS)
- XDG-compliant directory structure

## Quick Start

```bash
# Clone the repo
git clone https://github.com/yourusername/terminal-session-historian.git
cd terminal-session-historian

# Run the installer
./install.sh

# Edit your config
nano ~/.config/terminal-historian/config

# Start the service
systemctl --user start terminal-historian
```

## How It Works

```
┌─────────────────┐     ┌──────────────┐     ┌─────────────────┐
│  Shell History  │────▶│   Monitor    │────▶│   Raw History   │
│  ~/.bash_history│     │  (daemon)    │     │  (append-only)  │
│  Custom logs    │     └──────────────┘     └────────┬────────┘
└─────────────────┘                                   │
                                                      ▼
                                            ┌──────────────────┐
                                            │   Summarizer     │
                                            │  (periodic/manual)│
                                            └────────┬─────────┘
                                                     │
                                                     ▼
                                            ┌──────────────────┐
                                            │ Context Summary  │
                                            │   (markdown)     │
                                            └──────────────────┘
```

1. **Monitor** watches your configured sources (shell history, log files)
2. New activity is appended to the **raw history** file
3. **Summarizer** periodically generates a condensed **context summary**
4. Use the summary for documentation, auditing, or feeding to LLMs

## Installation

### Requirements

- Bash 4.0+
- systemd (optional, for background service)
- Standard Unix tools (grep, sed, tail, etc.)

### Install

```bash
git clone https://github.com/yourusername/terminal-session-historian.git
cd terminal-session-historian
./install.sh
```

The installer will:
1. Create config directory (`~/.config/terminal-historian/`)
2. Create data directory (`~/.local/share/terminal-historian/`)
3. Install scripts to `~/.local/bin/`
4. Optionally set up systemd user service

### Uninstall

```bash
./install.sh uninstall
```

This removes scripts and service but preserves your data.

## Configuration

Config file: `~/.config/terminal-historian/config`

```bash
# Primary shell history source (auto-detected if empty)
SHELL_ACTIVITY_SOURCE=""

# Additional directories to monitor (include AI agent logs!)
ADDITIONAL_LOG_DIRS="$HOME/.claude/projects"

# Check for new activity every N seconds
CHECK_INTERVAL=60

# Regenerate summary every N days
SUMMARY_INTERVAL=1

# LLM summarization via Claude API
LLM_SUMMARIZATION=true
CLAUDE_MODEL="claude-3-haiku-20240307"
```

See `config/historian.conf.example` for all options.

## Monitoring AI Coding Agents

One powerful use case is tracking your sessions with AI coding assistants like Claude Code. These tools generate extensive transcripts that are valuable for:

- **Context recovery** - Resume where you left off across sessions
- **Learning documentation** - Review how you solved problems with AI assistance
- **Project history** - Track architectural decisions and implementations

### Setting Up Claude Code Monitoring

Add Claude Code's project directory to your config:

```bash
ADDITIONAL_LOG_DIRS="$HOME/.claude/projects"
```

The monitor will automatically pick up `.jsonl` transcript files and include them in your history.

## Claude API Summarization

Instead of running a local LLM (which consumes significant RAM), you can use Claude's API for intelligent summarization.

### Why Claude API?

- **No local resources** - Doesn't compete with your other tools for RAM/CPU
- **Higher quality** - Claude produces excellent summaries of technical content
- **Token efficient** - The pending buffer approach only sends NEW content since last summary
- **Cost effective** - Using claude-3-haiku keeps costs minimal (~$0.001 per summary)

### Setup Steps

1. **Create an Anthropic account** at [console.anthropic.com](https://console.anthropic.com)

2. **Purchase API credits** - The API is separate from Claude Pro subscription
   - Go to Settings → Billing → Add credits
   - $5-10 is plenty for months of summarization

3. **Generate an API key**
   - Go to API Keys → Create Key
   - Name it something like "terminal-historian"

4. **Store your API key** (choose one method):
   ```bash
   # Option A: Config file (recommended)
   echo "your-api-key-here" > ~/.config/terminal-historian/api_key
   chmod 600 ~/.config/terminal-historian/api_key

   # Option B: Environment variable
   export ANTHROPIC_API_KEY="your-api-key-here"
   ```

5. **Enable in config**:
   ```bash
   LLM_SUMMARIZATION=true
   CLAUDE_MODEL="claude-3-haiku-20240307"
   ```

### How It Works: Pending Buffer Approach

The summarizer uses an incremental approach to save tokens:

```
┌────────────────────────────────────────────────────────────────┐
│                    Raw History File                            │
│  [===================|========================]                │
│   Already summarized   New content (pending)                   │
│         ↑                      ↓                               │
│   Position marker        Sent to LLM                           │
└────────────────────────────────────────────────────────────────┘
                                 │
                                 ▼
                    ┌─────────────────────┐
                    │  Rolling Summary    │
                    │  (appends over time)│
                    └─────────────────────┘
```

1. Tracks last summarized position (byte offset)
2. Only sends NEW content since last run to Claude API
3. Appends summary to rolling summary file
4. Updates position marker

This means even with hundreds of MB of history, each summarization call only processes recent activity.

## Usage

### Manual Commands

```bash
# Run monitor in foreground (useful for testing)
terminal-historian-monitor -f

# Single capture pass (useful for cron)
terminal-historian-monitor --once

# Generate summary now
terminal-historian-summarize

# Print summary to terminal
terminal-historian-summarize --stdout
```

### Systemd Service

```bash
# Start the service
systemctl --user start terminal-historian

# Enable on boot
systemctl --user enable terminal-historian

# Check status
systemctl --user status terminal-historian

# View logs
journalctl --user -u terminal-historian -f
```

## Output Files

| File | Location | Purpose |
|------|----------|---------|
| Raw history | `~/.local/share/terminal-historian/raw_history.txt` | Complete append-only log |
| Summary | `~/.local/share/terminal-historian/context_summary.md` | Static overview with stats |
| Rolling summary | `~/.local/share/terminal-historian/context_summary_rolling.md` | Incremental LLM summaries |
| Session logs | `~/.local/share/terminal-historian/sessions/` | Daily session files |
| Position state | `~/.local/state/terminal-historian/last_summarized_position` | Tracks summarization progress |
| Service log | `~/.local/share/terminal-historian/historian.log` | Daemon activity log |

## Use Cases

### Remembering Past Work
> "What commands did I run to fix that Docker networking issue last month?"

Search your raw history or check the summary.

### Documenting Procedures
> "I need to write docs for the server setup I just did."

Your session logs contain the exact commands in order.

### Creating Audit Trails
> "What changes were made to production last Tuesday?"

Session logs are dated and timestamped.

### LLM Context Loading
> "I want to ask an LLM about my project but it doesn't know my setup."

Feed it your context summary for instant background knowledge.

### Project Handoffs
> "New team member needs to understand our deployment process."

Share relevant session logs as real-world examples.

## Privacy

**Your raw data stays local.** History files never leave your machine.

- History stored in `~/.local/share/terminal-historian/`
- Config stored in `~/.config/terminal-historian/`
- API keys stored securely with restricted permissions
- No telemetry, no cloud sync

**If using Claude API summarization:** Recent activity content is sent to Anthropic's API for summarization. The API does not train on your data. If this is a concern, use local LLM summarization instead (e.g., Ollama).

The `.gitignore` ensures you never accidentally commit your personal data if you fork this repo.

## Contributing

Contributions welcome! Please:

1. Fork the repository
2. Create a feature branch
3. Submit a pull request

## License

MIT License - see [LICENSE](LICENSE) for details.

---

*Built for developers who believe in owning their data.*
