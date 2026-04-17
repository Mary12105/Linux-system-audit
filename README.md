# Linux System Audit and Monitoring
**NSCS — Academic Year 2025/2026 | Dr. BENTRAD Sassi**

---

## Project Structure

```
project/
├── main.sh          ← Start here. Interactive menu.
├── hardware.sh      ← Collects hardware data (CPU, RAM, Disk, Network, USB...)
├── software.sh      ← Collects OS/software data (packages, users, ports, security...)
├── report.sh        ← Filters, formats, displays, and saves reports
├── email.sh         ← Sends reports by email (msmtp / mailx / sendmail)
├── utils.sh         ← Shared colours, logging, and helper functions
├── config.conf      ← All settings — edit this file before running
├── reports/         ← Generated .txt, .html, .json report files
└── logs/
    └── audit.log    ← Execution log (every run is recorded here)
```

---

## Installation

### 1. Make scripts executable
```bash
chmod +x *.sh
```

### 2. Install required tools
```bash
# Ubuntu / Debian / Kali
sudo apt update
sudo apt install -y util-linux usbutils pciutils smartmontools \
                   sysstat msmtp msmtp-mta

# RHEL / Fedora / CentOS
sudo dnf install -y util-linux usbutils pciutils smartmontools sysstat msmtp
```

### 3. Edit the configuration file
```bash
nano config.conf
```
Set `EMAIL_RECIPIENT` to your email address at minimum.

---

## How to Run

```bash
# Interactive menu (recommended)
bash main.sh

# Run a short audit directly (for cron jobs)
bash main.sh --short

# Run a full audit directly
bash main.sh --full

# For complete output (dmidecode, fdisk, etc.)
sudo bash main.sh
```

---

## Menu Options

| # | Option | What it does |
|---|--------|-------------|
| 1 | Short audit | Runs a summary audit. Displays coloured output on the terminal, saves .txt/.html/.json files, then asks if you want to send by email. |
| 2 | Full audit | Same as short but collects every available detail. |
| 3 | Send latest by email | Sends the most recent .html, .txt, and .json reports to EMAIL_RECIPIENT. |
| 4 | View report directory | Lists all saved report files with size and date. |
| 5 | Clear old reports | Deletes reports older than LOG_RETENTION_DAYS days. |
| 6 | Exit | Exits the program. |

---

## Email Configuration (msmtp)

### Step 1 — Install msmtp
```bash
sudo apt install msmtp msmtp-mta
```

### Step 2 — Create ~/.msmtprc
```bash
nano ~/.msmtprc
```

Paste and fill in your details:
```
# Default settings for all accounts
defaults
auth           on
tls            on
tls_trust_file /etc/ssl/certs/ca-certificates.crt
logfile        ~/.msmtp.log

# --- Gmail ---
account        gmail
host           smtp.gmail.com
port           587
from           your.address@gmail.com
user           your.address@gmail.com
password       YOUR_APP_PASSWORD

# --- Outlook / Office 365 ---
# account        outlook
# host           smtp.office365.com
# port           587
# from           you@domain.com
# user           you@domain.com
# password       YOUR_PASSWORD

# Use gmail as default
account default : gmail
```

> **Gmail:** You must use an **App Password** — not your normal password.
> Go to: Google Account → Security → 2-Step Verification → App passwords → Create one for "Mail".

### Step 3 — Secure the file
```bash
chmod 600 ~/.msmtprc
```

### Step 4 — Test it
```bash
echo "Test from audit system" | msmtp your@email.com
```

### Step 5 — Update config.conf
```
EMAIL_RECIPIENT="your@email.com"
EMAIL_SENDER="your.address@gmail.com"
```

---

## Cron Job Setup

A cron job runs the audit automatically on a schedule without any manual action.

### Step 1 — Open the crontab editor
```bash
crontab -e
```
Choose `nano` if prompted.

### Step 2 — Add the audit job
Scroll to the bottom and add this line (replace the path with your actual project path):
```
0 4 * * * /bin/bash /full/path/to/project/main.sh --full >> /full/path/to/project/logs/cron.log 2>&1
```

**Example** (project is at /home/student/project):
```
0 4 * * * /bin/bash /home/student/project/main.sh --full >> /home/student/project/logs/cron.log 2>&1
```

### Step 3 — Save and verify
```bash
# Save: Ctrl+X → Y → Enter (in nano)
# Verify it was saved:
crontab -l
```

### Cron schedule format
```
MIN  HOUR  DAY  MONTH  WEEKDAY  command
 0    4     *    *       *      → every day at 04:00 AM
 */6  *     *    *       *      → every 6 hours
 0    4     *    *       1      → every Monday at 04:00 AM
 0    4     1    *       *      → 1st of every month at 04:00 AM
```

### For complete data, run as root
```bash
sudo crontab -e
# Add the same line — root has access to dmidecode, fdisk, lastb, etc.
```

### Check cron logs
```bash
cat logs/cron.log           # project cron output
cat logs/audit.log          # audit system execution log
grep CRON /var/log/syslog   # system cron activity
```

---
#This section is not working on this specific machine, you can configure it following these steps: 
## Remote Monitoring (SSH)

### Step 1 — Set up SSH key authentication
```bash
# Generate a key pair (skip if you already have one)
ssh-keygen -t ed25519

# Copy your public key to the remote machine
ssh-copy-id user@remote-host

# Test passwordless login
ssh user@remote-host "hostname"
```

### Step 2 — Configure config.conf
```
REMOTE_HOST="192.168.1.50"
REMOTE_USER="root"
REMOTE_PORT="22"
REMOTE_REPORT_DIR="/tmp/audit_reports"
```

### Step 3 — Run audit on remote machine
```bash
# Run hardware audit on remote, see results locally
ssh root@192.168.1.50 'bash -s' < hardware.sh

# Copy latest report to remote server
scp reports/latest.html root@192.168.1.50:/tmp/audit_reports/
```

---

## Report Files

Every audit run creates three files in the `reports/` directory:

| Format | Description |
|--------|-------------|
| `.txt` | Plain text. Readable anywhere. A `.sha256` hash file is created for integrity verification. |
| `.html` | Styled dark-theme web page. Open in any browser. |
| `.json` | Machine-readable. Use with `jq` or import into monitoring tools. |

### Verify report integrity
```bash
sha256sum -c hostname_2026-03-25_04-00-00_full.txt.sha256
# Output: hostname_..._full.txt: OK
```

---

## Troubleshooting

| Problem | Solution |
|---------|----------|
| Some sections show "Run as root" | Run with `sudo bash main.sh` |
| No colours in terminal | Run `export TERM=xterm-256color` |
| `lsusb: command not found` | `sudo apt install usbutils` |
| `dmidecode: command not found` | `sudo apt install dmidecode` |
| Email fails | Run `msmtp --debug your@email.com < /dev/null` |
| Cron job not running | Check `systemctl status cron` and `grep CRON /var/log/syslog` |

---

*Linux System Audit and Monitoring — NSCS 2025/2026 — Dr. BENTRAD Sassi*
