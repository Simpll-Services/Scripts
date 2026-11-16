#!/usr/bin/env sh
# Broadcast create-validator with keyring passphrase entry hidden (stty -echo).
# Run after recover-operator-key-hidden.sh and /root/validator.json exists.
# SSH only; bash <(curl ...) OK — not curl | sh.
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
VALIDATOR_JSON="${VALIDATOR_JSON:-/root/validator.json}"
CHAIN_ID="${CHAIN_ID:-tsc_87878-1}"
GAS_PRICES="${GAS_PRICES:-1000000000aTSC}"

if [ "$(id -u)" != "0" ]; then
  echo "Error: run as root."
  exit 1
fi

if [ ! -x "$TSCD" ]; then
  echo "Error: tscd not found at $TSCD"
  exit 1
fi

if [ ! -t 0 ]; then
  echo "Error: no TTY — use SSH."
  exit 1
fi

if [ ! -f "$VALIDATOR_JSON" ]; then
  echo "Error: missing $VALIDATOR_JSON"
  exit 1
fi

echo "Submitting create-validator (keyring passphrase typing is hidden)."
echo "Chain: $CHAIN_ID  File: $VALIDATOR_JSON"
echo ""
run_hidden "$TSCD" tx staking create-validator "$VALIDATOR_JSON" \
  --from "$KEY_NAME" --keyring-backend file \
  --chain-id "$CHAIN_ID" \
  --gas auto --gas-adjustment 1.5 --gas-prices "$GAS_PRICES" -y \
  $HOME_FLAG || exit $?

echo ""
echo "Done. Confirm with:"
echo "  curl -s http://127.0.0.1:26657/status | grep voting_power"
echo "  $TSCD q staking validators --node tcp://127.0.0.1:26657 -o json | jq -r '.validators[] | select(.description.moniker==\"MBV2026\") | .operator_address'"