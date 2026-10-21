#!/bin/bash
# Installs the sudoers rule that lets StayAwake toggle `pmset disablesleep`
# without a password. This is the ONLY privilege the app needs, and the only
# thing that makes "Allow Closed Lid" work. Run with:  sudo scripts/install-lid-mode.sh
# Remove with:                                         sudo scripts/install-lid-mode.sh --remove
set -euo pipefail

RULE_FILE=/etc/sudoers.d/stayawake
TARGET_USER="${SUDO_USER:-}"

if [ "$(id -u)" -ne 0 ]; then
  echo "run with sudo: sudo $0 $*" >&2; exit 1
fi
if [ -z "$TARGET_USER" ] || [ "$TARGET_USER" = "root" ]; then
  echo "could not determine the invoking user (SUDO_USER); run via sudo from your own account" >&2; exit 1
fi

if [ "${1:-}" = "--remove" ]; then
  rm -f "$RULE_FILE"
  /usr/bin/pmset disablesleep 0
  echo "removed $RULE_FILE and re-enabled sleep"
  exit 0
fi

TMP="$(mktemp)"
cat > "$TMP" <<RULE
# StayAwake: let $TARGET_USER toggle lid-closed sleep. Nothing else.
$TARGET_USER ALL=(root) NOPASSWD: /usr/bin/pmset disablesleep 0, /usr/bin/pmset disablesleep 1
RULE

# Validate before installing — a bad sudoers file can lock you out of sudo.
visudo -cf "$TMP" >/dev/null
install -m 0440 -o root -g wheel "$TMP" "$RULE_FILE"
rm -f "$TMP"

echo "installed $RULE_FILE"
echo "verify as $TARGET_USER with:  sudo -n -l /usr/bin/pmset disablesleep 1"
