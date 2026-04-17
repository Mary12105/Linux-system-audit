#!/usr/bin/env bash
# =============================================================================
# main.sh — Entry Point and Interactive Menu
# Linux System Audit and Monitoring — NSCS 2025/2026
#
# USAGE:
#   bash main.sh           — show the interactive menu
#   bash main.sh --short   — run a short audit and exit (non-interactive)
#   bash main.sh --full    — run a full audit and exit (non-interactive)
#   bash main.sh --help    — show usage
#
# MENU:
#   1) Short report  — summary, display on terminal + save files, ask to email
#   2) Full report   — detailed, display on terminal + save files, ask to email
#   3) Send latest reports by email  (txt, html, json)
#   4) View report directory
#   5) Clear old reports
#   6) Exit
# =============================================================================

# Resolve the project directory so all sourced scripts can find each other
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Load shared functions, configuration, report engine, and email module
source "${SCRIPT_DIR}/utils.sh"
source "${SCRIPT_DIR}/report.sh"
source "${SCRIPT_DIR}/email.sh"
# =============================================================================
# collect_data
# Runs hardware.sh and software.sh and stores their tagged output.
# The results are kept in global variables so a second audit in the same
# session can reuse the data without re-scanning the machine.
# =============================================================================
HW_RAW=""
SW_RAW=""

collect_data() {
    log_info "Collecting hardware information..."
    HW_RAW=$(bash "${SCRIPT_DIR}/hardware.sh" 2>/dev/null)

    if [[ -z "$HW_RAW" ]]; then
        log_warn "hardware.sh returned no data."
        HW_RAW="[HW:cpu]  Note:                        hardware.sh returned no output"
    fi

    log_info "Collecting software and OS information..."
    SW_RAW=$(bash "${SCRIPT_DIR}/software.sh" 2>/dev/null)

    if [[ -z "$SW_RAW" ]]; then
        log_warn "software.sh returned no data."
        SW_RAW="[SW:os]   Note:                        software.sh returned no output"
    fi

    log_ok "Data collection complete."
    echo ""
}

# =============================================================================
# run_audit
# Collects data, displays the coloured report on the terminal, saves the
# three report files, then asks the user if they want to send them by email.
# =============================================================================
run_audit() {
    local mode="$1"   # "short" or "full"

    # Always collect fresh data before running an audit
    collect_data

    # generate_reports (from report.sh):
    #   - displays the coloured report on the terminal
    #   - saves .txt, .html, and .json files
    generate_reports "$mode" "$HW_RAW" "$SW_RAW"

    # --- Ask the user if they want to send the reports by email ---
    echo ""
    echo "  ${C_KEY}Send the generated reports by email?${C_RESET}"
    echo ""
    echo "  ${C_VAL}1)${C_RESET} Yes — send HTML report"
    echo "  ${C_VAL}2)${C_RESET} Yes — send TXT report"
    echo "  ${C_VAL}3)${C_RESET} Yes — send all three formats"
    echo "  ${C_VAL}4)${C_RESET} No  — skip email"
    echo ""
    printf "  ${C_BOLD}Enter choice [1-4]:${C_RESET} "
    read -r email_choice

    case "$email_choice" in
        1) send_report "html" ;;
        2) send_report "txt"  ;;
        3)
            send_report "html"
            send_report "txt"
            send_report "json"
            ;;
        *) log_info "Email skipped." ;;
    esac
}

# =============================================================================
# send_all_latest
# Sends the latest html, txt, and json reports by email.
# =============================================================================
send_all_latest() {
    echo ""
    log_info "Sending latest reports by email..."
    send_report "html"
    send_report "txt"
    send_report "json"
}

# =============================================================================
# view_reports
# Lists all report files in the reports directory.
# =============================================================================
view_reports() {
    echo ""
    banner "REPORT DIRECTORY" "${REPORT_DIR}"
    echo ""

    # Count report files (not .sha256 hash files)
    local count
    count=$(find "${REPORT_DIR}" -maxdepth 1 -type f \( -name "*.txt" -o -name "*.html" -o -name "*.json" \) 2>/dev/null | wc -l)

    if [[ "$count" -eq 0 ]]; then
        echo "  ${C_WARN}No report files found.${C_RESET}"
        echo "  Run option 1 or 2 to generate reports first."
        echo ""
        return
    fi

    printf "  ${C_KEY}%-8s %-10s %-20s %s${C_RESET}\n" "Format" "Size" "Date" "Filename"
    echo "  ──────────────────────────────────────────────────────────────────"

    # List files sorted by modification time (newest first), skip hash files
    ls -lt "${REPORT_DIR}" 2>/dev/null \
        | grep -E '\.txt$|\.html$|\.json$' \
        | awk '{
            fmt = "txt"
            if ($NF ~ /\.html$/) fmt = "html"
            if ($NF ~ /\.json$/) fmt = "json"
            printf "  %-8s %-10s %-20s %s\n", fmt, $5, $6" "$7" "$8, $NF
          }'
    echo ""
    echo "  ${C_DIM}Total: ${count} report file(s)${C_RESET}"
    echo ""
}

# =============================================================================
# clear_old_reports
# Deletes report files older than LOG_RETENTION_DAYS days.
# =============================================================================
clear_old_reports() {
    local days="${LOG_RETENTION_DAYS:-30}"
    echo ""
    log_info "Removing reports older than ${days} days from ${REPORT_DIR}..."

    local before after deleted
    before=$(find "${REPORT_DIR}" -maxdepth 1 -type f 2>/dev/null | wc -l)
    find "${REPORT_DIR}" -maxdepth 1 -type f -mtime "+${days}" -delete 2>/dev/null
    after=$(find "${REPORT_DIR}" -maxdepth 1 -type f 2>/dev/null | wc -l)
    deleted=$(( before - after ))

    log_ok "Done. Deleted ${deleted} file(s). ${after} file(s) remain."
    echo ""
}

# =============================================================================
# show_menu — the interactive menu loop
# =============================================================================
show_menu() {
    while true; do
        clear

        banner "LINUX SYSTEM AUDIT AND MONITORING" "NSCS 2025/2026 — Dr. BENTRAD Sassi"

        echo ""
        echo "  ${C_KEY}What would you like to do?${C_RESET}"
        echo ""
        echo "  ${C_VAL}1)${C_RESET}  Run SHORT audit   (summary — faster)"
        echo "  ${C_VAL}2)${C_RESET}  Run FULL audit    (complete — more detailed)"
        echo "  ${C_VAL}3)${C_RESET}  Send latest reports by email"
        echo "  ${C_VAL}4)${C_RESET}  View report directory"
        echo "  ${C_VAL}5)${C_RESET}  Clear old reports (older than ${LOG_RETENTION_DAYS:-30} days)"
        echo "  ${C_VAL}6)${C_RESET}  Exit"
        echo ""

        printf "  ${C_BOLD}Enter choice [1-6]:${C_RESET} "
        read -r choice

        case "$choice" in
            1) run_audit "short" ;;
            2) run_audit "full"  ;;
            3) send_all_latest   ;;
            4) view_reports      ;;
            5) clear_old_reports ;;
            6)
                echo ""
                log_ok "Goodbye."
                echo ""
                exit 0
                ;;
            *)
                echo ""
                log_warn "Please enter a number between 1 and 6."
                ;;
        esac

        echo ""
        printf "  ${C_DIM}Press Enter to return to menu...${C_RESET} "
        read -r
    done
}

# =============================================================================
# Command-line mode (used by cron and for quick testing)
# =============================================================================
case "${1:-}" in
    --short|-s)
        collect_data
        generate_reports "short" "$HW_RAW" "$SW_RAW"

	send_report "txt"
        ;;
    --full|-f)
        collect_data
        generate_reports "full" "$HW_RAW" "$SW_RAW"

	#send automatically in non-interactive mode (for cron job automation)
	send_report "txt"
	send_report "html"
	send_report "json"
        ;;
    --help|-h)
        echo ""
        echo "Usage: bash main.sh [OPTION]"
        echo ""
        echo "  (no option)   Open the interactive menu"
        echo "  --short       Run a short audit and exit"
        echo "  --full        Run a full audit and exit"
        echo "  --help        Show this message"
        echo ""
        ;;
    "")
        show_menu
        ;;
    *)
        log_err "Unknown option: $1.  Run: bash main.sh --help"
        exit 1
        ;;
esac
