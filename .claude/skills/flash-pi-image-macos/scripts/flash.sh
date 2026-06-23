#!/usr/bin/env bash
# Flash a built omelet Pi image (.wic.bz2 / .wic / .img / .gz / .xz) to an SD card on macOS.
#
# Usage:
#   flash.sh [-y] /dev/diskN [image]
#
#   /dev/diskN   Target SD card. REQUIRED. Run `diskutil list` first to find it.
#   image        Optional. Defaults to the newest deploy/*.wic.bz2 in the repo.
#   -y, --yes    Skip the interactive type-the-disk-name confirmation.
#
# Sudo (the actual write needs root):
#   - Interactive TTY: sudo prompts for the password normally.
#   - Non-interactive (e.g. run from a tool/CI): export SUDO_PASSWORD=... and pass -y.
#     The image is decompressed to a temp file first so `dd` reads from a file and
#     stdin stays free to feed the password to `sudo -S` (avoids the
#     "a terminal is required to read the password" failure of `bzcat | sudo dd`).
#
# Safety: refuses the internal system disk, requires an explicit target, confirms before writing.
set -euo pipefail

err()  { printf '\033[31m%s\033[0m\n' "$*" >&2; }
note() { printf '\033[36m%s\033[0m\n' "$*"; }

usage() { sed -n '2,18p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; }

# --- repo root (skill lives in <repo>/.claude/skills/flash-pi-image-macos/scripts) ---
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../../.." && pwd)"

# --- parse args (flags + positional) ---
ASSUME_YES=0
POS=()
for a in "$@"; do
    case "$a" in
        -y|--yes) ASSUME_YES=1 ;;
        -h|--help) usage; exit 0 ;;
        -*) err "Unknown option: $a"; usage; exit 2 ;;
        *) POS+=("$a") ;;
    esac
done
DISK="${POS[0]:-}"
IMAGE="${POS[1]:-}"

if [[ -z "$DISK" ]]; then
    err "Usage: flash.sh [-y] /dev/diskN [image]"
    echo
    note "Attached disks:"
    diskutil list || true
    exit 2
fi

# Normalise: accept disk4 / /dev/disk4 / /dev/rdisk4 -> DISK=/dev/disk4, RDISK=/dev/rdisk4
[[ "$DISK" == /dev/* ]] || DISK="/dev/$DISK"
DISK="${DISK//\/dev\/rdisk//dev/disk}"   # collapse rdiskN -> diskN
BASE="$(basename "$DISK")"               # diskN
RDISK="/dev/r$BASE"                      # raw node for dd (faster)

# --- guardrails ---
if [[ "$BASE" == "disk0" ]]; then
    err "Refusing to write to $DISK (internal system disk)."
    exit 1
fi
if ! diskutil info "$DISK" >/dev/null 2>&1; then
    err "$DISK is not a valid disk. Run: diskutil list"
    exit 1
fi
# macOS reports the built-in SD reader as Location=Internal but Removable=Removable.
# Refuse only a truly fixed internal disk (e.g. disk0), not a removable card reader.
INFO="$(diskutil info "$DISK")"
LOC="$(awk -F: '/Device Location/   {gsub(/^[ \t]+/,"",$2); print $2; exit}' <<<"$INFO")"
REMOV="$(awk -F: '/Removable Media/ {gsub(/^[ \t]+/,"",$2); print $2; exit}' <<<"$INFO")"
if [[ "$LOC" == "Internal" && "$REMOV" != "Removable" ]]; then
    err "Refusing: $DISK is an internal, non-removable disk ($REMOV)."
    exit 1
fi

# --- pick image ---
if [[ -z "$IMAGE" ]]; then
    IMAGE="$(ls -t "$REPO"/deploy/*.wic.bz2 2>/dev/null | head -1 || true)"
    [[ -n "$IMAGE" ]] || { err "No deploy/*.wic.bz2 found. Run ./scripts/deploy-image.sh first."; exit 1; }
fi
[[ -f "$IMAGE" ]] || { err "Image not found: $IMAGE"; exit 1; }

# --- summary ---
SIZE="$(awk -F: '/Disk Size|Total Size/ {gsub(/^[ \t]+/,"",$2); print $2; exit}' <<<"$INFO")"
NAME="$(awk -F: '/Device \/ Media Name|Media Name/ {gsub(/^[ \t]+/,"",$2); print $2; exit}' <<<"$INFO")"
note "About to OVERWRITE this disk:"
echo "  Target : $DISK  ($NAME, $SIZE)"
echo "  Image  : $IMAGE"
echo
diskutil list "$DISK" || true
echo

# --- confirm ---
if [[ "$ASSUME_YES" -ne 1 ]]; then
    if [[ ! -t 0 ]]; then
        err "Non-interactive stdin: re-run with -y to skip confirmation (and set SUDO_PASSWORD)."
        exit 1
    fi
    read -r -p "Type the disk name to confirm (e.g. $BASE): " CONFIRM
    [[ "$CONFIRM" == "$BASE" ]] || { err "Confirmation '$CONFIRM' != '$BASE'. Aborted."; exit 1; }
fi

# --- prepare a raw source file (dd reads from a file so stdin can carry the sudo password) ---
TMP=""
cleanup() { [[ -n "$TMP" && -f "$TMP" ]] && rm -f "$TMP"; }
trap cleanup EXIT
case "$IMAGE" in
    *.bz2) DECOMP=bzcat ;;
    *.gz)  DECOMP=gzcat ;;
    *.xz)  DECOMP=xzcat ;;
    *)     DECOMP="" ;;
esac
if [[ -n "$DECOMP" ]]; then
    TMP="$(mktemp "${TMPDIR:-/tmp}/omelet-flash.XXXXXX.img")"
    note "Decompressing $(basename "$IMAGE") -> $TMP ..."
    "$DECOMP" "$IMAGE" > "$TMP"
    SRC="$TMP"
else
    SRC="$IMAGE"
fi

# --- flash ---
note "Unmounting $DISK ..."
diskutil unmountDisk "$DISK"

note "Writing $(basename "$SRC") -> $RDISK (Ctrl-T shows progress) ..."
if [[ -n "${SUDO_PASSWORD:-}" ]]; then
    printf '%s\n' "$SUDO_PASSWORD" | sudo -S dd if="$SRC" of="$RDISK" bs=4m
else
    sudo dd if="$SRC" of="$RDISK" bs=4m
fi

note "Syncing & ejecting ..."
sync
diskutil list "$DISK" || true
diskutil eject "$DISK"
note "Done. Card flashed with $(basename "$IMAGE") — safe to remove."
