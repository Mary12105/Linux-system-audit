#!/usr/bin/env bash
# =============================================================================
# utils.sh — Shared Utility Functions
# Project : Linux System Audit and Monitoring
#
# This file is SOURCED (not executed) by every other script:
#   source "$(dirname "$0")/utils.sh"
#
# Provides:
#   - Colour variables
#   - Formatted output helpers: section(), kv(), subheader(), banner()
#   - Logging helpers: log_info(), log_ok(), log_warn(), log_err()
#   - General helpers: cmd_exists(), strip_ansi(), confirm()
#   - Config loader: load_config()
# =============================================================================

# Guard against being sourced more than once
[[ -n "${_UTILS_LOADED:-}" ]] && return 0
_UTILS_LOADED=1

# ── Resolve the project root (directory containing utils.sh) ──────────────────
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ── Load config.conf ──────────────────────────────────────────────────────────
load_config() {
    local conf="${SCRIPT_DIR}/config.conf"
    if [[ -f "$conf" ]]; then
        # shellcheck source=config.conf
        source "$conf"
    else
        # Sensible defaults if config.conf is missing
        REPORT_DIR="${SCRIPT_DIR}/reports"
        LOG_FILE="${SCRIPT_DIR}/logs/audit.log"
        DEFAULT_MODE="full"
        DEFAULT_FORMAT="all"
        EMAIL_RECIPIENT=""
        LOG_RETENTION_DAYS=30
    fi

    # Ensure directories exist
    mkdir -p "$REPORT_DIR" 2>/dev/null
    mkdir -p "$(dirname "$LOG_FILE")" 2>/dev/null
}

# Load config immediately when this file is sourced
load_config

# ── Colour setup ──────────────────────────────────────────────────────────────
# Use hardcoded ANSI escape sequences instead of tput.
# tput requires a live TTY and a terminfo database — it silently produces
# empty strings inside subshells, pipelines, and cron jobs, causing all
# colour output to disappear. ANSI sequences work in every context.
#
# Only disable colours if stdout is not a terminal AND we are not in a
# context where the caller explicitly wants colours (e.g. report rendering).
# We check NO_COLOR (standard env var) and whether output is a plain file.
_ESC=$'\033'
if [[ "${NO_COLOR:-}" == "1" ]]; then
    # Explicitly disabled by caller
    C_HEADER="" C_KEY="" C_VAL="" C_OK="" C_INFO=""
    C_WARN="" C_ERR="" C_DANGER="" C_DIM="" C_BOLD="" C_RESET=""
else
    # Hardcoded ANSI sequences — work in subshells, pipelines, cron, SSH
    C_HEADER="${_ESC}[1;36m"   # bold cyan  → section titles
    C_KEY="${_ESC}[32m"        # green      → label names
    C_VAL="${_ESC}[37m"        # white      → values
    C_OK="${_ESC}[32m"         # green      → success messages
    C_INFO="${_ESC}[36m"       # cyan       → info messages
    C_WARN="${_ESC}[33m"       # yellow     → warnings
    C_ERR="${_ESC}[31m"        # red        → errors
    C_DANGER="${_ESC}[31m"     # red        → security alerts
    C_DIM="${_ESC}[2;37m"      # dim white  → supplementary hints
    C_BOLD="${_ESC}[1m"        # bold
    C_RESET="${_ESC}[0m"       # reset ALL formatting
fi

# =============================================================================
# Formatted output helpers
# =============================================================================

# Print a section separator with a title
# Usage: section "CPU Information"
section() {
    echo ""
    echo "${C_HEADER}══════════════════════════════════════════════════════"
    printf "  %s\n" "$1"
    echo "══════════════════════════════════════════════════════${C_RESET}"
}

# Print a key/value pair — label left-aligned in a 28-char column
# Usage: kv "Model" "Intel Core i7-12700"
kv() {
    printf "  ${C_KEY}%-28s${C_RESET} ${C_VAL}%s${C_RESET}\n" "$1:" "$2"
}

# Print a sub-header inside a section (used for grouped sub-blocks)
# Usage: subheader "Physical Memory Modules:"
subheader() {
    echo ""
    echo "  ${C_KEY}$1${C_RESET}"
}

# Print a full-width banner (used for script headers)
# Usage: banner "HARDWARE AUDIT" "SHORT SUMMARY REPORT"
banner() {
    local title="${1:-LINUX AUDIT}"
    local subtitle="${2:-}"
    echo ""
    echo "${C_HEADER}╔══════════════════════════════════════════════════════╗"
    printf  "║  %-52s║\n" "$title"
    [[ -n "$subtitle" ]] && printf "║   %-52s║\n" "$subtitle"
    echo    "╚══════════════════════════════════════════════════════╝${C_RESET}"
}

# =============================================================================
# Logging helpers
# All log_* functions write to stdout AND append to $LOG_FILE
# =============================================================================

# Internal: write a timestamped line to the log file
_log_write() {
    local level="$1"; shift
    local msg="$*"
    local ts
    ts=$(date '+%Y-%m-%d %H:%M:%S')
    echo "${ts}  [${level}]  ${msg}" >> "$LOG_FILE" 2>/dev/null
}

log_info()  {
    echo "${C_INFO}[INFO]${C_RESET}  $*"
    _log_write "INFO " "$*"
}

log_ok()    {
    echo "${C_OK}[OK]${C_RESET}    $*"
    _log_write "OK   " "$*"
}

log_warn()  {
    echo "${C_WARN}[WARN]${C_RESET}  $*"
    _log_write "WARN " "$*"
}

log_err()   {
    echo "${C_ERR}[ERROR]${C_RESET} $*" >&2
    _log_write "ERROR" "$*"
}

# =============================================================================
# General helpers
# =============================================================================

# Check whether a command is available on this system
# Usage: if cmd_exists lscpu; then ...
cmd_exists() { command -v "$1" &>/dev/null; }

# Strip ANSI colour escape codes from stdin
# Usage: echo "$coloured_text" | strip_ansi
strip_ansi() { sed 's/\x1b\[[0-9;]*m//g'; }

# Ask a yes/no question and return 0 for yes, 1 for no
# Usage: confirm "Generate full report?" && do_something
confirm() {
    local prompt="${1:-Are you sure?}"
    local answer
    printf "  %s [y/N] " "$prompt"
    read -r answer
    [[ "${answer,,}" == "y" || "${answer,,}" == "yes" ]]
}

# Check whether the script is running as root
is_root() { [[ $EUID -eq 0 ]]; }

# Warn if not root (non-fatal — some commands just produce less data)
warn_no_root() {
    ! is_root && \
        echo "  ${C_WARN}⚠  Run as root (sudo) for complete output in this section.${C_RESET}"
}

# Return the current timestamp in a filename-safe format
timestamp() { date '+%Y-%m-%d_%H-%M-%S'; }

# Escape text for safe embedding in HTML <pre> blocks
html_escape() { sed 's/&/\&amp;/g; s/</\&lt;/g; s/>/\&gt;/g'; }

# Clean up old report files beyond the retention window
# Usage: cleanup_old_reports
cleanup_old_reports() {
    local days="${LOG_RETENTION_DAYS:-30}"
    find "$REPORT_DIR" -type f -mtime "+${days}" -delete 2>/dev/null
    log_info "Old reports older than ${days} days removed."
}
