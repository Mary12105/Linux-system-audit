#!/usr/bin/env bash
# =============================================================================
# report.sh — Simplified Full-Mark Version
# =============================================================================

source "$(dirname "${BASH_SOURCE[0]}")/utils.sh"

# =============================================================================
# FILTER (short vs full)
# =============================================================================
filter_raw() {
    local mode="$1" raw="$2"

    [[ "$mode" == "short" ]] \
        && echo "$raw" | grep -v '^\[.*:full\]' \
        || echo "$raw"
}

# =============================================================================
# RENDER TAGS → COLOR OUTPUT
# =============================================================================
render() {
    while IFS= read -r line; do

        # ── Extract tag + content ─────────────────────────────
        if [[ "$line" =~ ^\[([^]]+)\][[:space:]]*(.*)$ ]]; then
            tag="${BASH_REMATCH[1]}"
            content="${BASH_REMATCH[2]}"
        else
            tag=""
            content="$line"
        fi

        # ── SECTION SEPARATORS (=== Hardware ===) ─────────────
        if [[ "$content" == *"==="* ]]; then
            echo ""
            echo "${C_HEADER}${content}${C_RESET}"
            continue
        fi

        # ── HEADER TYPE ────────────────────────────────────────
        if [[ "$tag" == *":header" ]]; then
            echo ""
            echo "${C_BOLD}${C_HEADER}${content}${C_RESET}"
            continue
        fi

        # ── KEY:VALUE LINES ───────────────────────────────────
        if [[ "$content" =~ ^[^:[:space:]][^:]*:[[:space:]]+.+$ ]]; then
            label="${content%%:*}"
            value="${content#*:}"

            printf "  ${C_KEY}%-25s${C_RESET} ${C_VAL}%s${C_RESET}\n" \
                "${label}:" "$value"
            continue
        fi

        # ── DEFAULT ────────────────────────────────────────────
        echo "$content"

    done
}
# =============================================================================
# HEADER
# =============================================================================
print_header() {
    banner "SYSTEM AUDIT REPORT" "$(date)"

    echo "Host   : $(hostname)"
    echo "Kernel : $(uname -r)"
    echo "User   : $(whoami)"
    echo ""
}

# =============================================================================
# SAVE TXT
# =============================================================================
save_txt() {
    local file="$1"
    if strip_ansi > "$file"; then
	    sha256sum "$file" > "${file}.sha256" 2>/dev/null
	    log_ok "TXT -> $file"
    else
	    echo "Failed to write report!"
    fi
}

# =============================================================================
# SAVE HTML
# =============================================================================
save_html() {
    local content="$1" file="$2"

    cat > "$file" <<EOF
<html>
<head>
<style>
body { background:#111; color:#eee; font-family:monospace; }
pre  { white-space:pre-wrap; }
</style>
</head>
<body>
<pre>
$(echo "$content" | strip_ansi | html_escape)
</pre>
</body>
</html>
EOF

    log_ok "HTML → $file"
}

# =============================================================================
# SAVE JSON (simple)
# =============================================================================
save_json() {
    local hw="$1" sw="$2" file="$3"

    cat > "$file" <<EOF
{
  "hostname": "$(hostname)",
  "kernel": "$(uname -r)",
  "hardware": $(printf '%s' "$hw" | jq -Rs .),
  "software": $(printf '%s' "$sw" | jq -Rs .)
}
EOF

    log_ok "JSON → $file"
}

# =============================================================================
# MAIN FUNCTION
# =============================================================================
generate_reports() {
    local mode="$1"
    local hw_raw="$2"
    local sw_raw="$3"

    mkdir -p "$REPORT_DIR"

    # --- FILTER ---
    hw=$(filter_raw "$mode" "$hw_raw")
    sw=$(filter_raw "$mode" "$sw_raw")

    # --- RENDER ---
    hw_out=$(echo "$hw" | render)
    sw_out=$(echo "$sw" | render)

    # --- DISPLAY ---
    print_header

    echo "${C_HEADER}=== HARDWARE ===========================================================================================================${C_RESET}"
    echo "$hw_out"

    echo -e "\n\n\n"
    echo "${C_HEADER}=== SOFTWARE ===========================================================================================================${C_RESET}"
    echo "$sw_out"

    # --- SAVE ---
    base="${REPORT_DIR}/report_$(date +%s)_${mode}"

    printf "%s\n%s\n" "$hw_out" "$sw_out" | save_txt "${base}.txt"
    save_html "$hw_out"$'\n'"$sw_out" "$base.html"
    save_json "$hw_out" "$sw_out" "$base.json"

    echo ""
    log_ok "Reports saved in $REPORT_DIR"
}
