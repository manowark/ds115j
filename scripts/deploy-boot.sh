#!/bin/bash
# deploy-boot.sh — versioned boot-image install / rollback on sda2.
# Run ON the NAS as root. Canonical copy is this repository.
#
# Deploys the uImage + HDD-initramfs pair as one set, keeps a rolling
# previous-image history on sda2, read-back-verifies hashes BEFORE umount,
# and never touches sda1/sda3, SPI, or U-Boot env.
set -euo pipefail

BOOT_DEV=/dev/sda2
MNT=/mnt/boot-deploy
HIST_KEEP=3

say() { printf '[deploy] %s\n' "$*"; }
die() { printf '[deploy] FATAL: %s\n' "$*" >&2; exit 1; }

usage() {
  cat <<'USAGE'
usage: deploy-boot.sh list
       deploy-boot.sh dry-prev
       deploy-boot.sh prev
       deploy-boot.sh <BUNDLE_DIR> [deploy|prev|list|dry-prev] [TAG]

  list          list sda2 boot images incl. rollback candidates; hash + date
                (BUNDLE_DIR optional; ignored)
  dry-prev      print which *.pre-* files prev would restore; do not write
  prev          rollback current uImage to newest uImage-ds115j.pre-*
                If no uRamdisk-hdd-ds115j.pre-* exists (ramdisk never
                changed), keep the current ramdisk. Never boots by itself —
                reboot separately with UART available.
  deploy        (default when BUNDLE_DIR is given) install uImage-ds115j +
                uRamdisk-hdd-ds115j from BUNDLE_DIR; previous pair saved as
                *.pre-<STAMP>[-TAG] on sda2

BUNDLE_DIR layout:
  uImage-ds115j          kernel uImage (kernel + appended DTB)
  uRamdisk-hdd-ds115j    HDD-root initramfs uImage
  MANIFEST               sha256sum lines for the above
USAGE
  exit 1
}

[ $# -lt 1 ] && usage

if [ "$1" = list ] || [ "$1" = prev ] || [ "$1" = dry-prev ]; then
  BUNDLE=/
  ACTION=$1
  TAG=${2:-}
else
  BUNDLE=$(readlink -f "$1")
  ACTION=${2:-deploy}
  TAG=${3:-}
fi

case "$ACTION" in
  deploy|prev|list|dry-prev) : ;;
  *) usage ;;
esac

# refuse to run while sda2 is already mounted somewhere
if mount | grep -q " ${BOOT_DEV} "; then
  die "$BOOT_DEV is already mounted elsewhere — refusing to double-mount"
fi

mkdir -p "$MNT"
if [ "$ACTION" = list ] || [ "$ACTION" = dry-prev ]; then
  mount -t ext2 -o ro "$BOOT_DEV" "$MNT" || die "mount -o ro $BOOT_DEV failed"
else
  mount -t ext2 "$BOOT_DEV" "$MNT" || die "mount $BOOT_DEV failed (cleanup: umount $MNT)"
fi
trap 'umount "$MNT" 2>/dev/null || true' EXIT

list() {
  echo "--- $BOOT_DEV ($MNT) ---"
  ls -l --full-time "$MNT/boot" 2>/dev/null
  echo "--- current pair ---"
  for f in uImage-ds115j uRamdisk-hdd-ds115j; do
    p="$MNT/boot/$f"
    if [ -f "$p" ]; then
      printf '%-46s %s  %s bytes\n' "$f" "$(sha256sum "$p" | awk '{print $1}')" "$(stat -c '%s' "$p")"
    else
      printf '%-46s MISSING\n' "$f"
    fi
  done
  echo "--- rollback candidates ---"
  found=0
  for f in "$MNT"/boot/uImage-ds115j.pre-* "$MNT"/boot/uRamdisk-hdd-ds115j.pre-*; do
    [ -e "$f" ] || continue
    found=1
    printf '%-46s %-16s %s bytes\n' "$(basename "$f")" "$(sha256sum "$f" | cut -c1-16)" "$(stat -c '%s' "$f")"
  done
  [ "$found" = 1 ] || echo "(none)"
}

pick_prev() {
  # sets K_PREV R_PREV; ramdisk may be the live file if no .pre-* exists
  K_PREV=$(ls -1t "$MNT"/boot/uImage-ds115j.pre-* 2>/dev/null | head -1) || true
  R_PREV=$(ls -1t "$MNT"/boot/uRamdisk-hdd-ds115j.pre-* 2>/dev/null | head -1) || true
  [ -n "$K_PREV" ] && [ -f "$K_PREV" ] || die "no rollback uImage candidate on sda2"
  if [ -z "$R_PREV" ] || [ ! -f "$R_PREV" ]; then
    R_PREV="$MNT/boot/uRamdisk-hdd-ds115j"
    [ -f "$R_PREV" ] || die "no current ramdisk to keep during kernel-only rollback"
    say "no ramdisk .pre-* history; prev would keep current uRamdisk-hdd-ds115j"
  fi
}

# verify_readback <mani>  — recompute hashes on the device, diff vs manifest
verify_readback() {
  local mani=$1 ok=1 dev want got
  for dev in uImage-ds115j uRamdisk-hdd-ds115j; do
    want=$(awk -v fn="$dev" '$2==fn {print $1}' "$mani")
    [ -n "$want" ] || die "MANIFEST has no entry for $dev"
    got=$(sha256sum "$MNT/boot/$dev" | awk '{print $1}')
    if [ "$want" != "$got" ]; then
      printf 'read-back MISMATCH %-22s want %s got %s\n' "$dev" "${want:0:16}" "${got:0:16}"
      ok=0
    else
      printf 'read-back OK      %-22s %s\n' "$dev" "${got:0:16}"
    fi
  done
  [ "$ok" = 1 ] || return 1
}

if [ "$ACTION" = list ]; then
  list
  exit 0
fi

if [ "$ACTION" = dry-prev ]; then
  pick_prev
  echo "dry-prev: would restore kernel  $(basename "$K_PREV")  $(sha256sum "$K_PREV" | awk '{print $1}')"
  echo "dry-prev: would restore ramdisk $(basename "$R_PREV")  $(sha256sum "$R_PREV" | awk '{print $1}')"
  echo "dry-prev: current kernel        $(sha256sum "$MNT/boot/uImage-ds115j" | awk '{print $1}')"
  echo "dry-prev: NO WRITE, NO REBOOT. Run: /root/deploy-boot.sh prev"
  echo "dry-prev: then reboot only with UART free. Newest kernel .pre-* is typically the alarm-gpios image — do not boot it unless diagnosing MUST-1."
  list
  exit 0
fi

if [ "$ACTION" = prev ]; then
  pick_prev
  STAMP=$(date -u +%Y%m%d-%H%M%S)
  cp -a "$MNT/boot/uImage-ds115j"       "$MNT/boot/uImage-ds115j.pre-$STAMP-pre-rollback"
  if [ "$R_PREV" != "$MNT/boot/uRamdisk-hdd-ds115j" ]; then
    cp -a "$MNT/boot/uRamdisk-hdd-ds115j" "$MNT/boot/uRamdisk-hdd-ds115j.pre-$STAMP-pre-rollback"
  fi
  cp -a "$K_PREV" "$MNT/boot/uImage-ds115j"
  if [ "$R_PREV" != "$MNT/boot/uRamdisk-hdd-ds115j" ]; then
    cp -a "$R_PREV" "$MNT/boot/uRamdisk-hdd-ds115j"
  fi
  ok=1
  [ "$(sha256sum "$MNT/boot/uImage-ds115j" | awk '{print $1}')" = "$(sha256sum "$K_PREV" | awk '{print $1}')" ] || ok=0
  [ "$(sha256sum "$MNT/boot/uRamdisk-hdd-ds115j" | awk '{print $1}')" = "$(sha256sum "$R_PREV" | awk '{print $1}')" ] || ok=0
  [ "$ok" = 1 ] || die "rollback read-back mismatch"
  printf 'rollback OK -> %s + %s (sync)\n' "$(basename "$K_PREV")" "$(basename "$R_PREV")"
  sync
  echo "NOTE: rollback is device-local; repository boot images are unchanged."
  echo "NOTE: files only — reboot separately with UART. Newest uImage .pre-* may be the alarm-gpios kernel."
  list
  exit 0
fi

# --- deploy ---
B_K="$BUNDLE/uImage-ds115j"
B_R="$BUNDLE/uRamdisk-hdd-ds115j"
B_M="$BUNDLE/MANIFEST"
[ -f "$B_K" ] || die "missing $B_K"
[ -f "$B_R" ] || die "missing $B_R"
[ -f "$B_M" ] || die "missing $B_M"

( cd "$BUNDLE" && sha256sum -c "$B_M" ) || die "bundle does not match its MANIFEST"

STAMP=$(date -u +%Y%m%d-%H%M%S)
SUF="$STAMP${TAG:+-$TAG}"

say "backing up current pair -> *.pre-$SUF"
cp -a "$MNT/boot/uImage-ds115j"       "$MNT/boot/uImage-ds115j.pre-$SUF"
cp -a "$MNT/boot/uRamdisk-hdd-ds115j" "$MNT/boot/uRamdisk-hdd-ds115j.pre-$SUF"
cp -a "$B_K" "$MNT/boot/uImage-ds115j"
cp -a "$B_R" "$MNT/boot/uRamdisk-hdd-ds115j"

say "pruning history (keep newest $HIST_KEEP)"
ls -1dt "$MNT"/boot/uImage-ds115j.pre-*     2>/dev/null | tail -n +$((HIST_KEEP+1)) | xargs -r rm -f
ls -1dt "$MNT"/boot/uRamdisk-hdd-ds115j.pre-* 2>/dev/null | tail -n +$((HIST_KEEP+1)) | xargs -r rm -f

verify_readback "$B_M" || {
  say "read-back FAILED — restoring previous pair"
  cp -a "$MNT/boot/uImage-ds115j.pre-$SUF" "$MNT/boot/uImage-ds115j"
  cp -a "$MNT/boot/uRamdisk-hdd-ds115j.pre-$SUF" "$MNT/boot/uRamdisk-hdd-ds115j"
  die "deploy aborted; previous pair restored"
}
sync
say "deployed $BUNDLE ($SUF) OK — sync'd, sda2 will be unmounted on exit"
list