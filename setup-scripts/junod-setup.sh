#!/bin/sh

set -a && . "$SCRIPT_PATH"/${1:-.env} && set +a
[ "$(id -un)" -ne "$VALIDATOR_USER" ] && echo "You must be $VALIDATOR_USER to run this script!" && exit 1

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

echo -n "[sudo] password for $USER: "
read -rs PASSWORD
echo "$PASSWORD" | sudo -S tee /etc/systemd/system/cosmovisor.service <<EOF
[Unit]
Description=cosmovisor
After=network-online.target

[Service]
Type=simple
User=$USER
WorkingDirectory=$HOME
ExecStart=$(which cosmovisor) start
Restart=on-failure
RestartSec=3
LimitNOFILE=65535
Environment="DAEMON_NAME=junod"
Environment="DAEMON_HOME=$DAEMON_HOME"
Environment="DAEMON_ALLOW_DOWNLOAD_BINARIES=false"
Environment="DAEMON_RESTART_AFTER_UPGRADE=true"

[Install]
WantedBy=multi-user.target
EOF

sudo systemctl daemon-reload
sudo systemctl enable cosmovisor
sudo systemctl start cosmovisor
