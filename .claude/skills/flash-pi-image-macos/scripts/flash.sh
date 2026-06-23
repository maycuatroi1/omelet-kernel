#!/usr/bin/env bash
# Flash a built omelet Pi image (.wic.bz2 or .wic/.img) to an SD card on macOS.
#
# Usage:
#   flash.sh /dev/diskN [image]
#
#   /dev/diskN   Target SD card (external/physical). REQUIRED. Run `diskutil list external physical` first.
#   image        Optional. Defaults to the newest deploy/*.wic.bz2 in the repo.
#
# Safety: refuses the internal disk0, refuses non-external disks, confirms before writing.
set -euo pipefail

err() { printf '\033[31m%s\033[0m\n' "$*" >&2; }
note() { printf '\033[36m%s\033[0m\n' "$*"; }

# --- repo root (skill lives in <repo>/.claude/skills/flash-pi-image-macos/scripts) ---
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../../.." && pwd)"

# --- args ---
DISK="${1:-}"
IMAGE="${2:-}"

if [[ -z "$DISK" ]]; then
    err "Usage: flash.sh /dev/diskN [image]"
    echo
    note "Available external/physical disks:"
    diskutil list external physical || true
    exit 2
fi

# Normalise /dev/diskN
[[ "$DISK" == /dev/* ]] || DISK="/dev/$DISK"
DISK="${DISK/\/dev\/rdisk//dev/disk}"   # collapse rdiskN -> diskN for diskutil
BASE="$(basename "$DISK")"               # diskN
RDISK="/dev/r$BASE"                      # raw node for dd

# --- guardrails ---
if [[ "$BASE" == "disk0" ]]; then
    err "Refusing to write to $DISK (internal system disk)."
    exit 1
fi
if ! diskutil info "$DISK" >/dev/null 2>&1; then
    err "$DISK is not a valid disk. Run: diskutil list external physical"
    exit 1
fi
INTERNAL="$(diskutil info "$DISK" | awk -F: '/Internal:/ {gsub(/ /,"",$2); print $2}')"
if [[ "$INTERNAL" == "Yes" ]]; then
    err "Refusing: $DISK is an INTERNAL disk. Only external SD cards are allowed."
    exit 1
fi

# --- pick image ---
if [[ -z "$IMAGE" ]]; then
    IMAGE="$(ls -t "$REPO"/deploy/*.wic.bz2 2>/dev/null | head -1 || true)"
    [[ -n "$IMAGE" ]] || { err "No deploy/*.wic.bz2 found. Run ./scripts/deploy-image.sh first."; exit 1; }
fi
[[ -f "$IMAGE" ]] || { err "Image not found: $IMAGE"; exit 1; }

# --- summary + confirm ---
SIZE="$(diskutil info "$DISK" | awk -F: '/Disk Size|Total Size/ {print $2; exit}' | sed 's/^ *//')"
NAME="$(diskutil info "$DISK" | awk -F: '/Device \/ Media Name|Media Name/ {print $2; exit}' | sed 's/^ *//')"
note "About to OVERWRITE this disk:"
echo "  Target : $DISK  ($NAME, $SIZE)"
echo "  Image  : $IMAGE"
echo
diskutil list "$DISK" || true
echo
read -r -p "Type the disk name to confirm (e.g. $BASE): " CONFIRM
[[ "$CONFIRM" == "$BASE" ]] || { err "Confirmation '$CONFIRM' != '$BASE'. Aborted."; exit 1; }

# --- flash ---
note "Unmounting $DISK ..."
diskutil unmountDisk "$DISK"

note "Writing to $RDISK (Ctrl-T shows progress) ..."
case "$IMAGE" in
    *.bz2)  DECOMP=(bzcat "$IMAGE") ;;
    *.gz)   DECOMP=(gzcat "$IMAGE") ;;
    *.xz)   DECOMP=(xzcat "$IMAGE") ;;
    *)      DECOMP=(cat "$IMAGE") ;;
esac
"${DECOMP[@]}" | sudo dd of="$RDISK" bs=4m

note "Syncing & ejecting ..."
sync
diskutil eject "$DISK"
note "Done. Card flashed with $(basename "$IMAGE") — safe to remove."
