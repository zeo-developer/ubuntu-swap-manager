#!/usr/bin/env bash
# =============================================================
#  Swap Manager for Ubuntu
#  1. Create swap   2. Delete swap   3. Tune swappiness   4. Show status
#  Usage:  sudo bash swap.sh
# =============================================================

set -o pipefail

SYSCTL_FILE="/etc/sysctl.d/99-swap.conf"
DEFAULT_SWAPFILE="/swapfile"

# ---------- Colors ----------
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; BOLD='\033[1m'; NC='\033[0m'

info()  { echo -e "${CYAN}[INFO]${NC} $*"; }
ok()    { echo -e "${GREEN}[OK]${NC} $*"; }
warn()  { echo -e "${YELLOW}[WARN]${NC} $*"; }
err()   { echo -e "${RED}[ERROR]${NC} $*" >&2; }
pause() { echo; read -rp "Press Enter to continue..." _; }

# ---------- Check root privileges ----------
if [[ $EUID -ne 0 ]]; then
    err "This script must be run as root. Please use: sudo bash $0"
    exit 1
fi

# ---------- Show status ----------
show_status() {
    echo -e "\n${BOLD}===== MEMORY STATUS =====${NC}"
    free -h
    echo -e "\n${BOLD}===== ACTIVE SWAP =====${NC}"
    if [[ -n "$(swapon --show --noheadings)" ]]; then
        swapon --show
    else
        warn "No active swap found."
    fi
    echo -e "\n${BOLD}Current swappiness:${NC} $(cat /proc/sys/vm/swappiness)"
    echo -e "${BOLD}Current vfs_cache_pressure:${NC} $(cat /proc/sys/vm/vfs_cache_pressure)"
}

# ---------- Convert size (e.g. 2G, 512M, 2) to MB ----------
size_to_mb() {
    local input="${1^^}"
    if [[ "$input" =~ ^([0-9]+)G?B?$ ]]; then
        echo $(( BASH_REMATCH[1] * 1024 ))
    elif [[ "$input" =~ ^([0-9]+)MB?$ ]]; then
        echo "${BASH_REMATCH[1]}"
    else
        return 1
    fi
}

# ---------- 1. Create swap ----------
create_swap() {
    echo -e "\n${BOLD}===== CREATE SWAP =====${NC}"
    local ram_mb suggest
    ram_mb=$(free -m | awk '/^Mem:/{print $2}')
    if   (( ram_mb <= 2048 )); then suggest="$(( ram_mb * 2 / 1024 + 1 ))G"
    elif (( ram_mb <= 8192 )); then suggest="$(( (ram_mb + 1023) / 1024 ))G"
    else suggest="4G"; fi
    info "Current RAM: ${ram_mb}MB — suggested swap size: ${suggest}"

    read -rp "Enter swap size (e.g. 2G, 512M) [${suggest}]: " size
    size="${size:-$suggest}"
    local size_mb
    if ! size_mb=$(size_to_mb "$size") || (( size_mb <= 0 )); then
        err "Invalid size: $size"; return
    fi

    read -rp "Swap file path [${DEFAULT_SWAPFILE}]: " swapfile
    swapfile="${swapfile:-$DEFAULT_SWAPFILE}"

    if [[ -e "$swapfile" ]]; then
        warn "File $swapfile already exists."
        read -rp "Overwrite (delete the old file and recreate)? [y/N]: " ans
        [[ "${ans,,}" == "y" ]] || { info "Cancelled."; return; }
        swapoff "$swapfile" 2>/dev/null
        rm -f "$swapfile"
    fi

    # Check available disk space
    local dir avail_mb
    dir=$(dirname "$swapfile")
    mkdir -p "$dir"
    avail_mb=$(df -Pm "$dir" | awk 'NR==2{print $4}')
    if (( avail_mb < size_mb + 100 )); then
        err "Not enough disk space. Available: ${avail_mb}MB, required: ${size_mb}MB"; return
    fi

    info "Creating ${size_mb}MB swap file at $swapfile ..."
    if ! fallocate -l "${size_mb}M" "$swapfile" 2>/dev/null; then
        warn "fallocate is not available, falling back to dd (may be slow)..."
        dd if=/dev/zero of="$swapfile" bs=1M count="$size_mb" status=progress || {
            err "Failed to create file."; rm -f "$swapfile"; return; }
    fi

    chmod 600 "$swapfile"
    mkswap "$swapfile" >/dev/null || { err "mkswap failed."; rm -f "$swapfile"; return; }
    swapon "$swapfile"         || { err "swapon failed."; rm -f "$swapfile"; return; }

    # Add to /etc/fstab so it is enabled automatically on boot
    if ! awk -v f="$swapfile" '$1==f{found=1} END{exit !found}' /etc/fstab; then
        cp /etc/fstab "/etc/fstab.bak.$(date +%Y%m%d%H%M%S)"
        echo "$swapfile none swap sw 0 0" >> /etc/fstab
        ok "Added to /etc/fstab (fstab backed up)."
    fi

    ok "Swap created successfully!"
    swapon --show
}

# ---------- 2. Delete swap ----------
delete_swap() {
    echo -e "\n${BOLD}===== DELETE SWAP =====${NC}"
    mapfile -t swaps < <(swapon --show=NAME,TYPE,SIZE --noheadings)
    if (( ${#swaps[@]} == 0 )); then
        warn "No active swap found."
        return
    fi

    local i
    for i in "${!swaps[@]}"; do
        echo "  $((i + 1)). ${swaps[$i]}"
    done
    echo "  0. Cancel"
    read -rp "Select swap to delete: " choice
    [[ "$choice" =~ ^[0-9]+$ ]] || { err "Invalid choice."; return; }
    (( choice == 0 )) && { info "Cancelled."; return; }
    (( choice >= 1 && choice <= ${#swaps[@]} )) || { err "Invalid choice."; return; }

    local name type
    name=$(awk '{print $1}' <<< "${swaps[$((choice - 1))]}")
    type=$(awk '{print $2}' <<< "${swaps[$((choice - 1))]}")

    read -rp "Confirm deleting swap $name? [y/N]: " ans
    [[ "${ans,,}" == "y" ]] || { info "Cancelled."; return; }

    info "Disabling swap $name ..."
    swapoff "$name" || { err "swapoff failed (there may not be enough free RAM to hold swapped data)."; return; }

    # Remove the corresponding entry from /etc/fstab
    if awk -v f="$name" '$1==f{found=1} END{exit !found}' /etc/fstab; then
        cp /etc/fstab "/etc/fstab.bak.$(date +%Y%m%d%H%M%S)"
        awk -v f="$name" '$1!=f' /etc/fstab > /etc/fstab.tmp && mv /etc/fstab.tmp /etc/fstab
        ok "Removed from /etc/fstab (fstab backed up)."
    fi

    if [[ "$type" == "file" && -f "$name" ]]; then
        rm -f "$name" && ok "Deleted file $name."
    elif [[ "$type" == "partition" ]]; then
        warn "$name is a partition — swap disabled only, the partition was not removed."
    fi

    ok "Swap deletion completed."
}

# ---------- Persist sysctl parameter ----------
persist_sysctl() {
    local key="$1" value="$2"
    touch "$SYSCTL_FILE"
    if grep -qE "^\s*${key}\s*=" "$SYSCTL_FILE"; then
        sed -i -E "s|^\s*${key}\s*=.*|${key} = ${value}|" "$SYSCTL_FILE"
    else
        echo "${key} = ${value}" >> "$SYSCTL_FILE"
    fi
}

# ---------- 3. Tune swap usage priority ----------
tune_swappiness() {
    echo -e "\n${BOLD}===== TUNE SWAP USAGE PRIORITY =====${NC}"
    echo "Current swappiness: $(cat /proc/sys/vm/swappiness)"
    echo
    echo "  Value from 0 - 100 (higher = more swap usage):"
    echo "   1. 10  - Server / VPS (recommended, prefer RAM)"
    echo "   2. 30  - Balanced"
    echo "   3. 60  - Ubuntu default"
    echo "   4. Enter a custom value"
    echo "   0. Cancel"
    read -rp "Choice: " c
    local val
    case "$c" in
        1) val=10 ;;
        2) val=30 ;;
        3) val=60 ;;
        4) read -rp "Enter swappiness (0-100): " val ;;
        0) info "Cancelled."; return ;;
        *) err "Invalid choice."; return ;;
    esac

    if ! [[ "$val" =~ ^[0-9]+$ ]] || (( val > 100 )); then
        err "Invalid value: $val"; return
    fi

    sysctl -w vm.swappiness="$val" >/dev/null
    persist_sysctl "vm.swappiness" "$val"
    ok "Set vm.swappiness = $val (persisted in $SYSCTL_FILE)."

    echo
    read -rp "Also tune vfs_cache_pressure (inode/dentry cache retention)? [y/N]: " ans
    if [[ "${ans,,}" == "y" ]]; then
        echo "  Current: $(cat /proc/sys/vm/vfs_cache_pressure) (default 100, recommended 50)"
        read -rp "Enter value [50]: " vcp
        vcp="${vcp:-50}"
        if [[ "$vcp" =~ ^[0-9]+$ ]]; then
            sysctl -w vm.vfs_cache_pressure="$vcp" >/dev/null
            persist_sysctl "vm.vfs_cache_pressure" "$vcp"
            ok "Set vm.vfs_cache_pressure = $vcp."
        else
            err "Invalid value."
        fi
    fi
}

# ---------- Main menu ----------
main_menu() {
    while true; do
        clear
        echo -e "${BOLD}${CYAN}"
        echo "╔══════════════════════════════════════╗"
        echo "║        SWAP MANAGER - UBUNTU         ║"
        echo "╚══════════════════════════════════════╝${NC}"
        echo -e " RAM: $(free -h | awk '/^Mem:/{print $3"/"$2}')   Swap: $(free -h | awk '/^Swap:/{print $3"/"$2}')   swappiness: $(cat /proc/sys/vm/swappiness)\n"
        echo "  1. Create swap"
        echo "  2. Delete swap"
        echo "  3. Tune swap usage priority (swappiness)"
        echo "  4. Show swap status"
        echo "  0. Exit"
        echo
        read -rp "Select an option [0-4]: " opt
        case "$opt" in
            1) create_swap;     pause ;;
            2) delete_swap;     pause ;;
            3) tune_swappiness; pause ;;
            4) show_status;     pause ;;
            0) echo "Goodbye!"; exit 0 ;;
            *) err "Invalid choice."; sleep 1 ;;
        esac
    done
}

main_menu
