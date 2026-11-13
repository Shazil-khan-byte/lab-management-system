#!/usr/bin/env bash
set -euo pipefail

GREEN=$(tput setaf 2 2>/dev/null || echo "")
YELLOW=$(tput setaf 3 2>/dev/null || echo "")
CYAN=$(tput setaf 6 2>/dev/null || echo "")
RED=$(tput setaf 1 2>/dev/null || echo "")
RESET=$(tput sgr0 2>/dev/null || echo "")

if [[ $EUID -ne 0 ]]; then
    echo -e "${RED}[ERROR] Please run with sudo: sudo bash setup_lab_server.sh${RESET}"
    exit 1
fi

echo -e "${CYAN}=== COLLEGE LAB SERVER PROVISIONING ===${RESET}"

echo -e "\n${YELLOW}[1/5] Verifying & installing required lab software packages...${RESET}"
PACKAGES=(gcc g++ python3 git vim htop net-tools tar gzip cron)
export DEBIAN_FRONTEND=noninteractive
if ping -c 1 -W 2 8.8.8.8 &>/dev/null; then
    apt-get -o Acquire::ForceIPv4=true update -qq || true
    apt-get -o Acquire::ForceIPv4=true install -y -qq "${PACKAGES[@]}" || true
    echo -e "${GREEN}[OK] Packages installed/verified via apt.${RESET}"
else
    echo -e "${YELLOW}[INFO] Offline mode detected — verifying pre-installed system packages:${RESET}"
    for pkg in "${PACKAGES[@]}"; do
        if dpkg -s "$pkg" &>/dev/null || command -v "$pkg" &>/dev/null; then
            echo "  - $pkg: INSTALLED"
        else
            echo "  - $pkg: QUEUED (requires network)"
        fi
    done
    echo -e "${GREEN}[OK] Offline package audit complete.${RESET}"
fi

echo -e "\n${YELLOW}[2/5] Creating department groups & 100 student accounts...${RESET}"
DEPTS=("cse" "ece" "mech")
for grp in "${DEPTS[@]}"; do
    getent group "$grp" >/dev/null || groupadd "$grp"
done

CREATED_COUNT=0
for i in $(seq -w 1 100); do
    USERNAME="student${i}"
    MOD=$((10#$i % 3))
    DEPT="${DEPTS[$MOD]}"
    if ! id "$USERNAME" &>/dev/null; then
        useradd -m -s /bin/bash -g "$DEPT" -G "$DEPT" "$USERNAME"
        echo "${USERNAME}:LabPass@2026" | chpasswd
        chage -d 0 "$USERNAME"
        ((CREATED_COUNT++)) || true
    fi
done
echo -e "${GREEN}[OK] 100 student accounts ready (Created: ${CREATED_COUNT}).${RESET}"

echo -e "\n${YELLOW}[3/5] Configuring departmental shared folders (/srv/lab_shared/)...${RESET}"
mkdir -p /srv/lab_shared
chmod 755 /srv/lab_shared
for grp in "${DEPTS[@]}"; do
    FOLDER="/srv/lab_shared/${grp^^}"
    mkdir -p "$FOLDER"
    chown root:"$grp" "$FOLDER"
    chmod 2770 "$FOLDER"
done
echo -e "${GREEN}[OK] Shared folders /srv/lab_shared/{CSE,ECE,MECH} configured with SGID (2770).${RESET}"

echo -e "\n${YELLOW}[4/5] Deploying automated lab cleanup script...${RESET}"
cat << 'CLEANUP' > /usr/local/bin/lab_cleanup.sh
#!/usr/bin/env bash
LOG_FILE="/var/log/lab_cleanup.log"
echo "[$(date '+%Y-%m-%d %H:%M:%S')] Starting automated lab cleanup..." >> "$LOG_FILE"
find /tmp -type f -mtime +1 -delete 2>/dev/null || true
for home_dir in /home/student*; do
    [[ -d "$home_dir/.cache" ]] && rm -rf "${home_dir}/.cache/"* 2>/dev/null || true
done
for sess_file in /home/*/lab_data/sessions.txt; do
    [[ -f "$sess_file" ]] && sed -i 's/|ACTIVE$/|AUTO_CLOSED/g' "$sess_file"
done
echo "[$(date '+%Y-%m-%d %H:%M:%S')] Cleanup completed." >> "$LOG_FILE"
CLEANUP
chmod 755 /usr/local/bin/lab_cleanup.sh
echo -e "${GREEN}[OK] Cleanup script ready at /usr/local/bin/lab_cleanup.sh.${RESET}"

echo -e "\n${YELLOW}[5/5] Scheduling automated cleanup & backups via cron...${RESET}"
cat << 'BACKUP' > /usr/local/bin/lab_scheduled_backup.sh
#!/usr/bin/env bash
BACKUP_DIR="/var/backups/college_lab"
mkdir -p "$BACKUP_DIR"
STAMP=$(date +%Y%m%d_%H%M%S)
ARCHIVE="${BACKUP_DIR}/full_lab_backup_${STAMP}.tar.gz"
tar -czf "$ARCHIVE" /srv/lab_shared /home/*/lab_data 2>/dev/null || true
ls -tp "${BACKUP_DIR}"/full_lab_backup_*.tar.gz 2>/dev/null | tail -n +8 | xargs -r rm --
echo "[$(date '+%Y-%m-%d %H:%M:%S')] Backup saved: $ARCHIVE" >> /var/log/lab_backup.log
BACKUP
chmod 755 /usr/local/bin/lab_scheduled_backup.sh

( (crontab -l 2>/dev/null || true) | grep -v "lab_cleanup.sh" | grep -v "lab_scheduled_backup.sh"; \
  echo "0 23 * * * /usr/local/bin/lab_cleanup.sh"; \
  echo "30 23 * * * /usr/local/bin/lab_scheduled_backup.sh" ) | crontab -

service cron start >/dev/null 2>&1 || true
echo -e "${GREEN}[OK] Cron scheduled: 23:00 Cleanup | 23:30 Backup.${RESET}"
echo -e "\n${CYAN}=== SETUP COMPLETE ===${RESET}"
