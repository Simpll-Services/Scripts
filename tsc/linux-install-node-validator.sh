#!/usr/bin/env sh
# Installs the TSC CLI, initializes the node, activates it, and sets up a validator node with statesync
# Simpll fork of TSC v4.0.2: same flow as upstream; tty echo is off only during keys add --recover
# so the mnemonic is not visible while typing. Run from a file in a real terminal (not curl | sh).
set -e

# Hide TTY echo while running a command that reads a mnemonic (stty, not read -s:
# the child is tsc/tscd, not our read). Restores echo even if the command fails.
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
  if [ "$hidden_rc" != 0 ]; then
    return "$hidden_rc"
  fi
}

# --- Parse arguments ---
USERNAME=""
LICENSE_KEY=""
OPERATOR=""
ACTIVATION_PK="${ACTIVATION_PK:-}"
ACTIVATION_KEY_FILE=""
SKIP_CHAIN_ACTIVATION=""
STAKE_AMOUNT=""
MONIKER=""
MIN_SELF_DELEGATION=""
COMMISSION_RATE=""
COMMISSION_MAX_RATE=""
COMMISSION_MAX_CHANGE_RATE=""
ENVIRONMENT=""
CHAIN_ID=""

usage() {
  echo "Usage: $0 -u <username> -l <license-key> -o <operator-address> -e <mainnet|testnet>"
  echo "          --chain-id <chain-id> --stake <amount> --moniker <name> --min-self-delegation <amount>"
  echo "          --commission-rate <rate> --commission-max-rate <rate> --commission-max-change-rate <rate>"
  echo "          [--activation-key-file <path> | -a <activation-pk> | --skip-chain-activation]"
  echo ""
  echo "  -u, --username               Account email address                    [env ACTIVATE_USERNAME]"
  echo "  -l, --license-key            License key                              [env ACTIVATE_LICENSE_KEY]"
  echo "  -o, --operator               Operator wallet address (bech32 or 0x)   [env ACTIVATE_OPERATOR]"
  echo "  -e, --environment            mainnet or testnet"
  echo "      --activation-key-file    File holding the activation private key (must be chmod 600)"
  echo "  -a, --activation-pk          Activation private key value (discouraged: visible in ps)"
  echo "      --skip-chain-activation  Do not activate the node on chain from this machine. The"
  echo "                               operator activates it on chain separately, using the node"
  echo "                               address printed here. No activation key is read."
  echo ""
  echo "The activation private key may also be supplied in the ACTIVATION_PK"
  echo "environment variable. When none is given, the CLI prompts for it."
}

while [ $# -gt 0 ]; do
  case "$1" in
    -u|--username)
      USERNAME="$2"
      shift 2
      ;;
    -l|--license-key|-k|--key)
      # -k/--key is the pre-4.0.0 spelling, kept so existing callers keep working
      LICENSE_KEY="$2"
      shift 2
      ;;
    -o|--operator)
      OPERATOR="$2"
      shift 2
      ;;
    -e|--environment)
      ENVIRONMENT="$2"
      shift 2
      ;;
    --chain-id)
      CHAIN_ID="$2"
      shift 2
      ;;
    --stake)
      STAKE_AMOUNT="$2"
      shift 2
      ;;
    --moniker)
      MONIKER="$2"
      shift 2
      ;;
    --min-self-delegation)
      MIN_SELF_DELEGATION="$2"
      shift 2
      ;;
    --commission-rate)
      COMMISSION_RATE="$2"
      shift 2
      ;;
    --commission-max-rate)
      COMMISSION_MAX_RATE="$2"
      shift 2
      ;;
    --commission-max-change-rate)
      COMMISSION_MAX_CHANGE_RATE="$2"
      shift 2
      ;;
    --activation-key-file)
      ACTIVATION_KEY_FILE="$2"
      shift 2
      ;;
    -a|--activation-pk)
      ACTIVATION_PK="$2"
      shift 2
      ;;
    --skip-chain-activation)
      SKIP_CHAIN_ACTIVATION="1"
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown option: $1"
      usage
      exit 1
      ;;
  esac
done

# Fall back to the environment variable names the CLI itself reads
[ -n "$USERNAME" ] || USERNAME="${ACTIVATE_USERNAME:-}"
[ -n "$LICENSE_KEY" ] || LICENSE_KEY="${ACTIVATE_LICENSE_KEY:-}"
[ -n "$OPERATOR" ] || OPERATOR="${ACTIVATE_OPERATOR:-}"

if [ -z "$USERNAME" ] || [ -z "$LICENSE_KEY" ] || [ -z "$OPERATOR" ] || [ -z "$ENVIRONMENT" ] || [ -z "$CHAIN_ID" ] || [ -z "$STAKE_AMOUNT" ] || [ -z "$MONIKER" ] || [ -z "$MIN_SELF_DELEGATION" ] || [ -z "$COMMISSION_RATE" ] || [ -z "$COMMISSION_MAX_RATE" ] || [ -z "$COMMISSION_MAX_CHANGE_RATE" ]; then
  usage
  exit 1
fi

if [ "$ENVIRONMENT" != "mainnet" ] && [ "$ENVIRONMENT" != "testnet" ]; then
  echo "Error: environment must be 'mainnet' or 'testnet'"
  usage
  exit 1
fi

# Checked before anything is installed, so the conflict fails fast.
if [ -n "$SKIP_CHAIN_ACTIVATION" ] && { [ -n "$ACTIVATION_KEY_FILE" ] || [ -n "$ACTIVATION_PK" ]; }; then
  echo "Error: --skip-chain-activation reads no activation key, so do not also give"
  echo "--activation-key-file, --activation-pk or ACTIVATION_PK"
  exit 1
fi

# --- Require root ---
# `tsc node ...` refuses to run as a non-root user on linux: the node is a
# root-owned systemd service with its files under root's home.
if [ "$(id -u)" != "0" ]; then
  echo "Error: this script must be run as root (e.g. sudo $0 ...)"
  exit 1
fi

# --- Set download URL based on architecture ---
version="4.0.2"
case "$(uname -m)" in
  x86_64|amd64) arch="amd64" ;;
  aarch64|arm64) arch="arm64" ;;
  *)
    echo "Error: unsupported architecture: $(uname -m)"
    exit 1
    ;;
esac
binary="trust_${version}_linux_${arch}"
release_url="https://github.com/TrustedSmartChain/trust-node-releases/releases/download/v${version}"

# --- Download CLI ---
node="/opt/tsc/bin/tsc"
curl -fsSL "$release_url/$binary" -o $node --create-dirs
expected=$(curl -fsSL "$release_url/checksums.txt" | grep " $binary$" | cut -d' ' -f1)
echo "$expected  $node" | sha256sum -c -
chmod +x $node

# ADD ALIAS
alias='alias tsc="/opt/tsc/bin/tsc"'
if ! grep -Fxq "$alias" ~/.bashrc; then
    echo $alias >> ~/.bashrc
fi

$node version

# --- Initialize node ---
set +e
$node node init -e "$ENVIRONMENT"
exit_code=$?
set -e
if [ "$exit_code" != 0 ] && [ $exit_code != 99 ]; then
  exit 1
fi

# --- Install and start node service ---
$node node service install
$node node service start

# --- Activate node ---
# The license key goes in the environment rather than on the command line so it
# stays out of `ps`. The activation private key is never accepted as a flag
# value: the CLI reads it from a 0600 file, a file descriptor, stdin, or a
# hidden prompt.
TMP_KEY_FILE=""
cleanup_key() {
  if [ -n "$TMP_KEY_FILE" ]; then
    rm -f "$TMP_KEY_FILE"
    TMP_KEY_FILE=""
  fi
}
trap cleanup_key EXIT HUP INT TERM

KEY_FILE=""
if [ -n "$ACTIVATION_KEY_FILE" ]; then
  KEY_FILE="$ACTIVATION_KEY_FILE"
elif [ -n "$ACTIVATION_PK" ]; then
  TMP_KEY_FILE="$(mktemp)"
  chmod 600 "$TMP_KEY_FILE"
  printf '%s\n' "$ACTIVATION_PK" > "$TMP_KEY_FILE"
  KEY_FILE="$TMP_KEY_FILE"
fi

set +e
if [ -n "$SKIP_CHAIN_ACTIVATION" ]; then
  # The node service activation still runs. The node sends no on-chain status
  # or attestations until the operator activates it on chain, then starts by
  # itself. The validator steps below do not wait for that.
  ACTIVATE_LICENSE_KEY="$LICENSE_KEY" $node node activate \
    -u "$USERNAME" -o "$OPERATOR" --skip-chain-activation
elif [ -n "$KEY_FILE" ]; then
  ACTIVATE_LICENSE_KEY="$LICENSE_KEY" $node node activate \
    -u "$USERNAME" -o "$OPERATOR" --activation-key-file "$KEY_FILE"
else
  ACTIVATE_LICENSE_KEY="$LICENSE_KEY" $node node activate \
    -u "$USERNAME" -o "$OPERATOR"
fi
activate_rc=$?
set -e
cleanup_key

if [ "$activate_rc" = 2 ]; then
  echo ""
  echo "The node is registered on chain but node service activation did not finish."
  echo "Re-run this script to complete it; the on-chain step is skipped on the re-run."
  exit 2
fi
if [ "$activate_rc" != 0 ]; then
  exit 1
fi

# --- Add validator workload ---
$node workloads add tsc.chain.validator

# --- Install validator node ---
# tsc validator install may run `tscd init --recover` and echo the mnemonic; hide it.
echo "If asked for a bip39 mnemonic here, typing is hidden."
run_hidden $node validator install -e "$ENVIRONMENT" || exit $?

# --- Pause before configure ---
echo ""
echo "Make sure your sentry node is fully configured and running before continuing."
echo ""
printf "Ready to continue? (y/n): "
read CONFIRM
if [ "$CONFIRM" != "y" ] && [ "$CONFIRM" != "Y" ]; then
  echo "Aborted."
  exit 1
fi

# --- Configure validator with statesync ---
$node validator configure --statesync

# --- Start validator node ---
$node validator start

# --- Wait for node to sync before creating validator ---
echo ""
echo "Waiting for node to sync..."
echo "Once the node is fully synced, the validator setup will continue."
echo ""

tscd="/opt/tsc/bin/tscd"
while true; do
  CATCHING_UP=$(${tscd} status 2>&1 | grep -o '"catching_up":[a-z]*' | cut -d: -f2)
  if [ "$CATCHING_UP" = "false" ]; then
    echo "Node is synced!"
    break
  fi
  echo "Still syncing... (catching_up=$CATCHING_UP)"
  sleep 30
done

# --- Get validator pubkey ---
echo ""
PUBKEY=$(${tscd} comet show-validator)
echo "Validator pubkey: $PUBKEY"

# --- Create validator.json ---
cat > /root/validator.json <<VALJSON
{
  "pubkey": $PUBKEY,
  "amount": "${STAKE_AMOUNT}aTSC",
  "moniker": "$MONIKER",
  "commission-rate": "$COMMISSION_RATE",
  "commission-max-rate": "$COMMISSION_MAX_RATE",
  "commission-max-change-rate": "$COMMISSION_MAX_CHANGE_RATE",
  "min-self-delegation": "$MIN_SELF_DELEGATION"
}
VALJSON

echo ""
echo "Created /root/validator.json"
echo ""

# --- Add operator key to keyring ---
echo "Recovering operator key into keyring..."
echo "You will be prompted for your mnemonic and a keyring passphrase."
echo "Characters are hidden while you type."
echo ""
run_hidden ${tscd} keys add operator --recover --keyring-backend file || exit $?

# --- Submit create-validator transaction ---
echo ""
echo "Submitting create-validator transaction..."
${tscd} tx staking create-validator /root/validator.json --from operator --keyring-backend file --chain-id "$CHAIN_ID" --fees 1000000000aTSC --gas auto --gas-adjustment 1.5 -y

echo ""
echo "Validator setup complete!"
