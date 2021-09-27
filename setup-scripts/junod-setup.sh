#!/bin/sh

SCRIPT_PATH="$( cd -- "$(dirname "$0")" >/dev/null 2>&1 ; pwd -P )"
set -a && . "$SCRIPT_PATH"/${1:-.env} && set +a
[ "$(id -un)" != "$VALIDATOR_USER" ] && echo "You must be $VALIDATOR_USER to run this script!" && exit 1

. "$HOME"/.profile
cd && git clone https://github.com/CosmosContracts/juno.git
cd juno
git checkout "$JUNO_TAG"
make install

junod init "$MONIKER" --chain-id="$CHAIN_ID"
curl "$GENESIS_URL" > ~/.juno/config/genesis.json

[ -n "$PEERS_URL" ] && sed -i "s/^persistent_peers *=.*/persistent_peers = \"$(curl -s "$PEERS_URL")\"/" ~/.juno/config/config.toml
[ -n "$SEEDS_URL" ] && sed -i "s/^seeds *=.*/seeds = \"$(curl -s "$SEEDS_URL")\"/" ~/.juno/config/config.toml
sed -i "s/^prometheus *=.*/prometheus = \"true\"/" ~/.juno/config/config.toml

junod config chain-id "$CHAIN_ID"

go install github.com/cosmos/cosmos-sdk/cosmovisor/cmd/cosmovisor@latest
cat >> "$HOME"/.profile << EOF
export DAEMON_NAME=junod
export DAEMON_HOME=$HOME/.juno
EOF
. "$HOME"/.profile
mkdir -p "$DAEMON_HOME"/cosmovisor/genesis/bin
mkdir -p "$DAEMON_HOME"/cosmovisor/upgrades

cp "$(which junod)" "$DAEMON_HOME"/cosmovisor/genesis/bin
