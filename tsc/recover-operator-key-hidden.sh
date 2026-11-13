#!/usr/bin/env sh
# Recover the operator key into the file keyring with terminal echo disabled.
# Use from an SSH session (not the DO web console). Do not pipe: bash <(curl ...) is OK;
# curl ... | sh is not (no TTY).
set -e

run_hidden() {
  old_stty=""
  if [ -t 0 ]; then
    old_stty=$(stty -g)
    stty -echo
    trap 'stty "$old_stty"; exit 130' INT TERM
  fi
  set +e
  set +x
  "$@"
  hidden_rc=$?
  if [ -n "$old_stty" ]; then
    stty "$old_stty"
    trap - INT TERM
  fi
  set -e
  return "$hidden_rc"
}

TSCD="${TSCD:-/opt/tsc/bin/tscd}"
HOME_FLAG="${TSC_HOME:+--home $TSC_HOME}"
KEY_NAME="${KEY_NAME:-operator}"

if [ "$(id -u)" != "0" ]; then
  echo "Error: run as root (same as tsc chain service)."
  exit 1
fi

if [ ! -x "$TSCD" ]; then
  echo "Error: tscd not found at $TSCD"
  exit 1
fi

if [ ! -t 0 ]; then
  echo "Error: no TTY — use SSH, not 'curl | sh' or non-interactive shells."
  exit 1
fi

echo "Operator key recover (typing is hidden)."
echo "You will be prompted for the mnemonic and a new keyring passphrase."
echo ""
run_hidden "$TSCD" keys add "$KEY_NAME" --recover --keyring-backend file $HOME_FLAG || exit $?

echo ""
echo "Done. Verify:"
echo "  $TSCD keys show $KEY_NAME -a --keyring-backend file $HOME_FLAG"
