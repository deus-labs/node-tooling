#!/bin/sh

USERNAME=${1:-juno}
CHAIN_ID=${2:-juno-1}
EXPORT_PATH=${3:-/junotools-snapshots}
PARSER_PATH=${4:-$HOME/junotools-scripts}
PARSER_COMMAND=${5:-npm run parser}

HOME=/home/"$USERNAME"
. "$HOME"/.profile

LATEST_BLOCK=$("$DAEMON_NAME" status | jq -r '.SyncInfo.latest_block_height')
EXPORT_FILENAME=export-"$CHAIN_ID"-"$LATEST_BLOCK".json

systemctl stop cosmovisor 
su "$USERNAME" -c "$(which "$DAEMON_NAME") export --home $DAEMON_HOME > $EXPORT_PATH/$EXPORT_FILENAME 2>&1"
systemctl start cosmovisor

cd "$PARSER_PATH" && echo "$PARSER_COMMAND $EXPORT_PATH/$EXPORT_FILENAME" | sh

