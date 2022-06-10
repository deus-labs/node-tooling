#!/bin/sh

USERNAME=${1:-juno}
CHAIN_ID=${2:-juno-1}
EXPORT_PATH=${2:-/junotools-snapshots}

HOME=/home/"$USERNAME"
. "$HOME"/.profile

LATEST_BLOCK=$(junod status | jq -r '.SyncInfo.latest_block_height')
EXPORT_FILENAME=export-"$CHAIN_ID"-"$LATEST_BLOCK".json

systemctl stop cosmovisor 
$DAEMON_NAME export --home "$DAEMON_HOME" > "$EXPORT_PATH/$EXPORT_FILENAME"
systemctl start cosmovisor
