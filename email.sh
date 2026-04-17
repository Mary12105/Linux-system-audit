#!/usr/bin/env bash
# =============================================================================
# email.sh — Simplified (msmtp only)
# =============================================================================

source "$(dirname "${BASH_SOURCE[0]}")/utils.sh"

# =============================================================================
# GET LATEST FILE
# =============================================================================
latest() {
    ls -t "$REPORT_DIR"/*."$1" 2>/dev/null | head -1
}

# =============================================================================
# SEND REPORT
# =============================================================================
send_report() {
    local fmt="${1:-html}"

    # --- Validate config ---
    [[ -z "$EMAIL_RECIPIENT" ]] && {
        log_err "Set EMAIL_RECIPIENT in config.conf"
        return 1
    }

    cmd_exists msmtp || {
        log_err "msmtp not installed"
        return 1
    }

    # --- Find file ---
    file=$(latest "$fmt")

    [[ -z "$file" ]] && {
        log_err "No .$fmt report found"
        return 1
    }

    # --- MIME type ---
    case "$fmt" in
        html) mime="text/html" ;;
        json) mime="application/json" ;;
        *)    mime="text/plain" ;;
    esac

    subject="[Audit] $(hostname) - ${fmt^^} - $(date '+%H:%M')"

    log_info "Sending $fmt report..."

    {
        echo "From: ${EMAIL_SENDER:-audit@localhost}"
        echo "To: $EMAIL_RECIPIENT"
        echo "Subject: $subject"
        echo "MIME-Version: 1.0"
        echo "Content-Type: $mime; charset=UTF-8"
        echo ""
        cat "$file"
    } | msmtp --file="/root/.msmtprc" "$EMAIL_RECIPIENT"

    if [[ $? -eq 0 ]]; then
        log_ok "Email sent"
    else
        log_err "Failed (check msmtp config)"
    fi
}

# =============================================================================
# CLI MODE
# =============================================================================
[[ "${BASH_SOURCE[0]}" == "$0" ]] && send_report "$1"
