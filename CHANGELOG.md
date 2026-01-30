# Changelog

All notable changes to Terminal Session Historian will be documented in this file.

## [Unreleased]

### Added
- **Claude API Integration** - Native support for Claude API summarization as an alternative to local LLMs
  - Uses claude-3-haiku for cost-effective, high-quality summaries
  - API key can be stored in `~/.config/terminal-historian/api_key` or via `ANTHROPIC_API_KEY` environment variable

- **Incremental Pending Buffer Summarization** - Token-efficient approach that only processes new content
  - Tracks last summarized position (byte offset) in state file
  - Only sends content added since last summarization to LLM
  - Dramatically reduces API costs for large history files

- **Rolling Summary File** - Summaries now accumulate over time
  - New summaries append to `context_summary_rolling.md` instead of overwriting
  - Each entry is timestamped with line count
  - Provides historical record of activity summaries

- **AI Agent Monitoring** - Documentation and support for monitoring AI coding assistants
  - Claude Code transcript monitoring via `ADDITIONAL_LOG_DIRS`
  - Captures `.jsonl` transcript files automatically
  - Useful for context recovery and project documentation

### Changed
- Updated README with comprehensive Claude API setup instructions
- Added state directory (`~/.local/state/terminal-historian/`) for position tracking
- Improved summarizer to handle very large history files efficiently
- Updated privacy section to clarify API data handling

### Technical Details

The pending buffer approach works as follows:

1. **Position Tracking**: Stores byte offset of last summarized position
2. **Incremental Read**: Uses `tail -c +N` to read only new content
3. **Size Limiting**: Caps content sent to API at ~50KB per call
4. **Atomic Updates**: Position only updated after successful API call

This allows the historian to maintain hundreds of MB of raw history while keeping each API call minimal.

## [1.0.0] - 2025-01-29

### Added
- Initial release
- Shell history monitoring daemon
- Configurable log source monitoring
- LLM-powered summarization (local LLM support)
- Systemd service integration
- Daily session logs
- XDG-compliant directory structure
