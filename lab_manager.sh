#!/bin/bash 
#=======================================================
# COLLEGE COMPUTER LABORATORY MANAGEMENT SYSTEM
# Linux Micro Project - Bash Shell Scripting
#=======================================================

# Configuration & Data Storage Paths
DATA_DIR="$HOME/lab_data"
SYSTEMS="$DATA_DIR/systems.txt"
STUDENTS="$DATA_DIR/students.txt"
SESSIONS="$DATA_DIR/sessions.txt"
BOOKINGS="$DATA_DIR/bookings.txt"
FAULTS="$DATA_DIR/faults.txt"
BACKUP_DIR="$DATA_DIR/backup"

# Color Codes via tput
RED=$(tput setaf 1)
GREEN=$(tput setaf 2)
YELLOW=$(tput setaf 3)
CYAN=$(tput setaf 6)
BOLD=$(tput bold)
RESET=$(tput sgr0)

# Trap Ctrl+C (SIGINT) for clean exit
trap 'echo -e "\n${YELLOW}Interrupted. Exiting safely...${RESET}"; exit 1' SIGINT

# Helper Functions
msg_ok()   { echo -e "${GREEN}[OK] $1${RESET}"; }
msg_err()  { echo -e "${RED}[ERROR] $1${RESET}"; }
msg_info() { echo -e "${YELLOW}[INFO] $1${RESET}"; }

pause() {
    echo
    read -rp "Press Enter to continue..."
}

header() {
    clear
    echo -e "${CYAN}${BOLD}=== $1 ===${RESET}\n"
}

system_exists()  { grep -q "^$1|" "$SYSTEMS" 2>/dev/null; }
student_exists() { grep -q "^$1|" "$STUDENTS" 2>/dev/null; }

system_status() {
    grep "^$1|" "$SYSTEMS" 2>/dev/null | cut -d'|' -f3
}

set_status() {
    local target_id="$1"
    local new_status="$2"
    sed -i "s/^${target_id}|\([^|]*\)|.*/${target_id}|\1|${new_status}/" "$SYSTEMS"
}

init() {
    mkdir -p "$DATA_DIR" "$BACKUP_DIR"
    for f in "$SYSTEMS" "$STUDENTS" "$SESSIONS" "$BOOKINGS" "$FAULTS"; do
        [ -f "$f" ] || touch "$f"
    done

    # Preload default machines if empty
    if [ ! -s "$SYSTEMS" ]; then
        for i in 01 02 03 04 05; do
            echo "PC$i|Lab-PC-$i|Available" >> "$SYSTEMS"
        done
    fi
}

# 1. Add System
add_system() {
    header "ADD NEW COMPUTER"
    read -rp "System ID (format PC01): " id
    id=$(echo "$id" | tr '[:lower:]' '[:upper:]')
    if [[ ! "$id" =~ ^PC[0-9]{2}$ ]]; then
        msg_err "Invalid ID format. Use format PC01 to PC99."
        return
    fi
    if system_exists "$id"; then
        msg_err "System $id already exists."
        return
    fi
    read -rp "System Name / Model: " name
    [ -z "$name" ] && { msg_err "Name cannot be empty."; return; }
    name=$(echo "$name" | tr '|' '-')
    echo "$id|$name|Available" >> "$SYSTEMS"
    msg_ok "System $id added successfully."
}

# 2. View Systems
view_systems() {
    header "ALL COMPUTER SYSTEMS"
    if [ ! -s "$SYSTEMS" ]; then
        msg_info "No systems found in inventory."
        return
    fi
    printf "%-10s %-25s %-12s\n" "SYSTEM ID" "SYSTEM NAME" "STATUS"
    echo "--------------------------------------------------"
    sort "$SYSTEMS" | awk -F'|' '{printf "%-10s %-25s %-12s\n", $1, $2, $3}'
}

# 3. Register Student
register_student() {
    header "REGISTER STUDENT"
    read -rp "Roll number (5-15 letters/digits): " roll
    roll=$(echo "$roll" | tr '[:lower:]' '[:upper:]')
    if [[ ! "$roll" =~ ^[A-Z0-9]{5,15}$ ]]; then
        msg_err "Invalid roll number. Alphanumeric 5-15 characters required."
        return
    fi
    if student_exists "$roll"; then
        msg_err "Student with roll number $roll is already registered."
        return
    fi
    read -rp "Full Name: " name
    if [[ ! "$name" =~ ^[A-Za-z[:space:]]+$ ]]; then
        msg_err "Name must contain letters and spaces only."
        return
    fi
    read -rp "Department (e.g. CSE, ECE, MECH): " dept
    [ -z "$dept" ] && { msg_err "Department cannot be empty."; return; }
    dept=$(echo "$dept" | tr '[:lower:]' '[:upper:]' | tr '|' '-')

    echo "$roll|$name|$dept" >> "$STUDENTS"
    msg_ok "Student $name ($roll) registered successfully."
}

# 4. Check-in
check_in() {
    header "STUDENT CHECK-IN"
    read -rp "Roll number: " roll
    roll=$(echo "$roll" | tr '[:lower:]' '[:upper:]')
    student_exists "$roll" || { msg_err "Student not registered. Please register first."; return; }

    if grep -q "^$roll|.*|ACTIVE$" "$SESSIONS" 2>/dev/null; then
        msg_err "Student $roll already has an active session."
        return
    fi

    echo "Available systems:"
    local avail_count
    avail_count=$(grep -c "|Available$" "$SYSTEMS" 2>/dev/null)
    if [ "$avail_count" -eq 0 ]; then
        msg_err "No systems are currently available."
        return
    fi
    grep "|Available$" "$SYSTEMS" | awk -F'|' '{printf " - %s (%s)\n", $1, $2}'
    echo

    read -rp "Enter system ID: " sys
    sys=$(echo "$sys" | tr '[:lower:]' '[:upper:]')
    system_exists "$sys" || { msg_err "System $sys does not exist."; return; }

    if [ "$(system_status "$sys")" != "Available" ]; then
        msg_err "System $sys is not available (Current: $(system_status "$sys"))."
        return
    fi

    local current_date current_time
    current_date=$(date +%F)
    current_time=$(date +%H:%M)

    echo "$roll|$sys|$current_date|$current_time|-|ACTIVE" >> "$SESSIONS"
    set_status "$sys" "InUse"
    msg_ok "Checked in $roll on $sys at $current_time."
}

# 5. Check-out
check_out() {
    header "STUDENT CHECK-OUT"
    read -rp "Roll number: " roll
    roll=$(echo "$roll" | tr '[:lower:]' '[:upper:]')

    local line
    line=$(grep "^$roll|.*|ACTIVE$" "$SESSIONS" 2>/dev/null)
    if [ -z "$line" ]; then
        msg_err "No active session found for roll number $roll."
        return
    fi

    local sys now
    sys=$(echo "$line" | cut -d'|' -f2)
    now=$(date +%H:%M)

    sed -i "/^${roll}|.*|ACTIVE$/s/|-|ACTIVE$/|${now}|DONE/" "$SESSIONS"

    if [ "$(system_status "$sys")" = "InUse" ]; then
        set_status "$sys" "Available"
    fi
    msg_ok "Checked out $roll from $sys at $now."
}

# 6. View Active Sessions
view_sessions() {
    header "CURRENT ACTIVE SESSIONS"
    local active
    active=$(grep "|ACTIVE$" "$SESSIONS" 2>/dev/null)
    if [ -z "$active" ]; then
        msg_info "No active sessions currently running."
        return
    fi
    printf "%-14s %-10s %-12s %-8s\n" "ROLL NO" "SYSTEM" "DATE" "LOGIN"
    echo "--------------------------------------------------"
    echo "$active" | awk -F'|' '{printf "%-14s %-10s %-12s %-8s\n", $1, $2, $3, $4}'
}

# 7. Book Slot
book_slot() {
    header "BOOK A LAB SLOT"
    read -rp "Roll number: " roll
    roll=$(echo "$roll" | tr '[:lower:]' '[:upper:]')
    student_exists "$roll" || { msg_err "Student not registered."; return; }

    read -rp "System ID: " sys
    sys=$(echo "$sys" | tr '[:lower:]' '[:upper:]')
    system_exists "$sys" || { msg_err "System $sys does not exist."; return; }

    read -rp "Date (YYYY-MM-DD): " d
    if ! date -d "$d" +%F >/dev/null 2>&1 || [[ ! "$d" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]]; then
        msg_err "Invalid date format. Use YYYY-MM-DD."
        return
    fi
    if [[ "$d" < "$(date +%F)" ]]; then
        msg_err "Cannot book a date in the past."
        return
    fi

    echo -e "\nAvailable Slot Timings:"
    echo " 1) 09:00-11:00"
    echo " 2) 11:00-13:00"
    echo " 3) 14:00-16:00"
    echo " 4) 16:00-18:00"
    read -rp "Choose slot (1-4): " s
    case "$s" in
        1) slot="09:00-11:00" ;;
        2) slot="11:00-13:00" ;;
        3) slot="14:00-16:00" ;;
        4) slot="16:00-18:00" ;;
        *) msg_err "Invalid choice. Please select 1, 2, 3, or 4."; return ;;
    esac

    if grep -q "^[^|]*|${sys}|${d}|${slot}$" "$BOOKINGS" 2>/dev/null; then
        msg_err "System $sys is already booked on $d during $slot."
        return
    fi

    echo "$roll|$sys|$d|$slot" >> "$BOOKINGS"
    msg_ok "Slot booked successfully: $sys on $d ($slot)."
}

# 8. View Bookings
view_bookings() {
    header "ALL LAB BOOKINGS"
    if [ ! -s "$BOOKINGS" ]; then
        msg_info "No advance bookings found."
        return
    fi
    printf "%-14s %-10s %-12s %-14s\n" "ROLL NO" "SYSTEM" "DATE" "SLOT"
    echo "--------------------------------------------------------"
    sort -t'|' -k3 "$BOOKINGS" | awk -F'|' '{printf "%-14s %-10s %-12s %-14s\n", $1, $2, $3, $4}'
}

# 9. Fault Management
report_fault() {
    header "REPORT SYSTEM FAULT"
    read -rp "System ID: " sys
    sys=$(echo "$sys" | tr '[:lower:]' '[:upper:]')
    system_exists "$sys" || { msg_err "System does not exist."; return; }

    read -rp "Describe the issue: " desc
    [ -z "$desc" ] && { msg_err "Description cannot be empty."; return; }
    desc=$(echo "$desc" | tr '|' '/')

    local count fid
    count=$(wc -l < "$FAULTS" 2>/dev/null || echo 0)
    fid="F$((count + 1))"

    echo "$fid|$sys|$desc|$(date +%F)|OPEN" >> "$FAULTS"
    set_status "$sys" "Faulty"
    msg_ok "Fault ticket $fid logged. System $sys status set to Faulty."
}

# 10. Resolve Fault
resolve_fault() {
    header "RESOLVE SYSTEM FAULT"
    local open_faults
    open_faults=$(grep "|OPEN$" "$FAULTS" 2>/dev/null)
    if [ -z "$open_faults" ]; then
        msg_info "No open faults to resolve."
        return
    fi

    printf "%-8s %-10s %-30s\n" "FAULT ID" "SYSTEM" "ISSUE"
    echo "--------------------------------------------------"
    echo "$open_faults" | awk -F'|' '{printf "%-8s %-10s %-30s\n", $1, $2, $3}'
    echo

    read -rp "Enter Fault ID to resolve (e.g. F1): " fid
    fid=$(echo "$fid" | tr '[:lower:]' '[:upper:]')

    local line
    line=$(grep "^${fid}|.*|OPEN$" "$FAULTS" 2>/dev/null)
    if [ -z "$line" ]; then
        msg_err "No open ticket found with Fault ID $fid."
        return
    fi

    local sys
    sys=$(echo "$line" | cut -d'|' -f2)
    sed -i "s/^${fid}|\(.*\)|OPEN$/${fid}|\1|RESOLVED/" "$FAULTS"

    # Set back to Available only if no other active faults exist on this PC
    if ! grep -q "^[^|]*|${sys}|.*|OPEN$" "$FAULTS" 2>/dev/null; then
        set_status "$sys" "Available"
    fi
    msg_ok "Fault $fid resolved successfully. System status updated."
}

# 11. View Fault Log
view_faults() {
    header "FAULT INCIDENT LOG"
    if [ ! -s "$FAULTS" ]; then
        msg_info "Fault log is empty."
        return
    fi
    printf "%-8s %-8s %-12s %-10s %-25s\n" "ID" "SYSTEM" "DATE" "STATUS" "DESCRIPTION"
    echo "------------------------------------------------------------------"
    awk -F'|' '{printf "%-8s %-8s %-12s %-10s %-25s\n", $1, $2, $4, $5, $3}' "$FAULTS"
}

# 12. Search History
search_student() {
    header "SEARCH STUDENT HISTORY"
    read -rp "Enter Roll Number or Student Name: " key
    [ -z "$key" ] && { msg_err "Search input cannot be empty."; return; }

    local matches
    matches=$(grep -i "$key" "$STUDENTS" 2>/dev/null)
    if [ -z "$matches" ]; then
        msg_err "No registered student matching '$key' was found."
        return
    fi

    echo "$matches" | while IFS='|' read -r roll name dept; do
        echo -e "\n${BOLD}Record: $roll - $name ($dept)${RESET}"
        local count
        count=$(grep -c "^$roll|" "$SESSIONS" 2>/dev/null)
        echo "Total Lab Sessions: $count"
        if [ "$count" -gt 0 ]; then
            printf "  %-10s %-12s %-8s %-8s %-8s\n" "SYSTEM" "DATE" "IN" "OUT" "STATE"
            grep "^$roll|" "$SESSIONS" | awk -F'|' '{printf "  %-10s %-12s %-8s %-8s %-8s\n", $2, $3, $4, $5, $6}'
        fi
    done
}

# 13. Summary Report
generate_report() {
    header "LABORATORY SUMMARY REPORT ($(date '+%d-%b-%Y %H:%M'))"
    local total avail inuse faulty studs today openf

    total=$(grep -c "^" "$SYSTEMS" 2>/dev/null)
    avail=$(grep -c "|Available$" "$SYSTEMS" 2>/dev/null)
    inuse=$(grep -c "|InUse$" "$SYSTEMS" 2>/dev/null)
    faulty=$(grep -c "|Faulty$" "$SYSTEMS" 2>/dev/null)
    studs=$(grep -c "^" "$STUDENTS" 2>/dev/null)
    today=$(grep -c "|$(date +%F)|" "$SESSIONS" 2>/dev/null)
    openf=$(grep -c "|OPEN$" "$FAULTS" 2>/dev/null)

    total=${total:-0}; avail=${avail:-0}; inuse=${inuse:-0}
    faulty=${faulty:-0}; studs=${studs:-0}; today=${today:-0}; openf=${openf:-0}

    echo "=== Computer Systems ==="
    printf "  %-24s: %d\n" "Total Registered Systems" "$total"
    printf "  %-24s: %d\n" "Available for Use" "$avail"
    printf "  %-24s: %d\n" "Currently In-Use" "$inuse"
    printf "  %-24s: %d\n" "Under Maintenance" "$faulty"

    echo -e "\n=== Lab Activity ==="
    printf "  %-24s: %d\n" "Registered Students" "$studs"
    printf "  %-24s: %d\n" "Sessions Today" "$today"
    printf "  %-24s: %d\n" "Open Fault Tickets" "$openf"

    if [ -s "$SESSIONS" ]; then
        local top
        top=$(cut -d'|' -f2 "$SESSIONS" | sort | uniq -c | sort -rn | head -1)
        if [ -n "$top" ]; then
            echo -e "\n=== Peak Utilization ==="
            echo "  Most Utilized Machine : $(echo "$top" | awk '{print $2 " (" $1 " session(s))"}')"
        fi
    fi

    if [ -s "$STUDENTS" ]; then
        echo -e "\n=== Department Distribution ==="
        cut -d'|' -f3 "$STUDENTS" | sort | uniq -c | awk '{printf "  %-10s : %d student(s)\n", $2, $1}'
    fi
}

# 14. Backup
backup_data() {
    header "BACKUP LABORATORY DATA"
    local timestamp file
    timestamp=$(date +%Y%m%d_%H%M%S)
    file="$BACKUP_DIR/lab_backup_${timestamp}.tar.gz"

    if tar -czf "$file" -C "$DATA_DIR" systems.txt students.txt sessions.txt bookings.txt faults.txt 2>/dev/null; then
        msg_ok "Archive created: $file"
        ls -lh "$file" | awk '{print "Archive Size: " $5}'
    else
        msg_err "Failed to create archive backup."
    fi
}

# Main Interactive Menu
main_menu() {
    while true; do
        clear
        echo -e "${CYAN}${BOLD}====================================================${RESET}"
        echo -e "${CYAN}${BOLD}      COLLEGE COMPUTER LABORATORY MANAGEMENT        ${RESET}"
        echo -e "${CYAN}${BOLD}====================================================${RESET}"
        echo " 1.  Add Computer System"
        echo " 2.  View All Systems"
        echo " 3.  Register Student"
        echo " 4.  Student Check-In"
        echo " 5.  Student Check-Out"
        echo " 6.  View Active Sessions"
        echo " 7.  Book Lab Slot"
        echo " 8.  View All Bookings"
        echo " 9.  Report System Fault"
        echo " 10. Resolve System Fault"
        echo " 11. View Fault Log"
        echo " 12. Search Student History"
        echo " 13. Generate Summary Report"
        echo " 14. Backup Laboratory Data"
        echo " 0.  Exit"
        echo "----------------------------------------------------"
        read -rp "Enter choice [0-14]: " choice
        case "$choice" in
            1)  add_system ;;
            2)  view_systems ;;
            3)  register_student ;;
            4)  check_in ;;
            5)  check_out ;;
            6)  view_sessions ;;
            7)  book_slot ;;
            8)  view_bookings ;;
            9)  report_fault ;;
            10) resolve_fault ;;
            11) view_faults ;;
            12) search_student ;;
            13) generate_report ;;
            14) backup_data ;;
            0)  echo -e "\n${GREEN}Thank you for using Lab Manager. Exiting...${RESET}\n"; exit 0 ;;
            *)  msg_err "Invalid selection '$choice'. Please enter 0 to 14." ;;
        esac
        pause
    done
}

# Entry Point Execution
init
main_menu
