#!/bin/sh

USERNAME=${1:-grafana}
SCRIPT_PATH="$( cd -- "$(dirname "$0")" >/dev/null 2>&1 ; pwd -P )"

apt-get install -y apt-transport-https
apt-get install -y software-properties-common wget
wget -q -O - https://packages.grafana.com/gpg.key | apt-key add -

echo "deb https://packages.grafana.com/oss/deb stable main" >>/etc/apt/sources.list.d/grafana.list
apt-get update
apt-get install -y grafana

## prometheus
groupadd --system prometheus
useradd -s /sbin/nologin --system -g prometheus prometheus
mkdir /var/lib/prometheus
for i in rules rules.d files_sd; do mkdir -p /etc/prometheus/${i}; done
mkdir -p /tmp/prometheus && cd /tmp/prometheus

curl -s https://api.github.com/repos/prometheus/prometheus/releases/latest | grep browser_download_url | grep linux-amd64 | cut -d '"' -f 4 | wget -qi -
tar xvf prometheus*.tar.gz
cd prometheus*/
mv prometheus promtool /usr/local/bin/
mv prometheus.yml /etc/prometheus/prometheus.yml
mv consoles/ console_libraries/ /etc/prometheus/

cat >/etc/systemd/system/prometheus.service <<EOF
[Unit]
Description=Prometheus
Documentation=https://prometheus.io/docs/introduction/overview/
Wants=network-online.target
After=network-online.target

[Service]
Type=simple
User=prometheus
Group=prometheus
ExecReload=/bin/kill -HUP \$MAINPID
ExecStart=/usr/local/bin/prometheus \
  --config.file=/etc/prometheus/prometheus.yml \
  --storage.tsdb.path=/var/lib/prometheus \
  --web.console.templates=/etc/prometheus/consoles \
  --web.console.libraries=/etc/prometheus/console_libraries \
  --web.listen-address=0.0.0.0:9000 \
  --web.external-url=

SyslogIdentifier=prometheus
Restart=always

[Install]
WantedBy=multi-user.target
EOF

for i in rules rules.d files_sd; do chown -R prometheus:prometheus /etc/prometheus/${i}; done
for i in rules rules.d files_sd; do chmod -R 775 /etc/prometheus/${i}; done
chown -R prometheus:prometheus /var/lib/prometheus/

# edit manually afterwards
cp "$SCRIPT_PATH"/config/prometheus/prometheus-example.yml /etc/prometheus/prometheus.yml

## node_exporter
cd /home/"$USERNAME"
wget https://github.com/prometheus/node_exporter/releases/download/v1.2.1/node_exporter-1.2.1.linux-amd64.tar.gz

tar xvfz node_exporter-1.2.1.linux-amd64.tar.gz
cd node_exporter-1.2.1.linux-amd64
chmod +x node_exporter

cat >/etc/systemd/system/node-exporter-prometheus.service <<EOF
[Unit]
Description=Prometheus Node Exporter
After=network.target

[Service]
Type=simple
User=$USERNAME
WorkingDirectory=/home/$USERNAME
ExecStart=/home/$USERNAME/node_exporter-1.2.1.linux-amd64/node_exporter
Restart=on-failure

[Install]
WantedBy=multi-user.target
EOF

## panic_alerter
cd /home/"$USERNAME"
apt-get install -y python3-pip
su "$USERNAME" -c "pip install pipenv"

apt-get install -y redis-server

REDIS_PASS=$(tr -dc A-Za-z0-9 </dev/urandom | head -c 16)
sed -i "s/^# *requirepass.*/requirepass $REDIS_PASS/" /etc/redis/redis.conf

git clone https://github.com/SimplyVC/panic_cosmos.git
cd panic_cosmos

# interactive setup
# /home/"$USERNAME"/.local/bin/pipenv sync
# /home/"$USERNAME"/.local/bin/pipenv run python run_setup.py

cp "$SCRIPT_PATH"/config/panic_cosmos/*.ini /home/"$USERNAME"/panic_cosmos/config

sed -i -e "s/^password *=.*/password = $REDIS_PASS/" \
-e "s/^bot_token *=.*/bot_token = $TELEGRAM_BOT_TOKEN/g" \
-e "s/^bot_chat_id *=.*/bot_chat_id = $TELEGRAM_BOT_CHAT_ID/g" \
/home/"$USERNAME"/panic_cosmos/config/user_config_main.ini

/home/"$USERNAME"/.local/bin/pipenv sync

chown -R "$USERNAME":"$USERNAME" /home/"$USERNAME"/panic_cosmos/
chmod -R 700 /home/"$USERNAME"/panic_cosmos/logs
chmod +x /home/"$USERNAME"/panic_cosmos/run_setup.py
chmod +x /home/"$USERNAME"/panic_cosmos/run_alerter.py

cd /home/"$USERNAME"/panic_cosmos
su "$USERNAME" -c "/home/$USERNAME/.local/bin/pipenv sync"

cat >/etc/systemd/system/panic_alerter.service <<EOF
[Unit]
Description=PANIC
After=network.target
StartLimitIntervalSec=0

[Service]
Type=simple
Restart=always
User="$USERNAME"
TimeoutStopSec=90s
WorkingDirectory=/home/$USERNAME/panic_cosmos/
ExecStart=/home/$USERNAME/.local/bin/pipenv run python /home/$USERNAME/panic_cosmos/run_alerter.py

[Install]
WantedBy=multi-user.target
EOF

## cosmos-exporter
cd /home/"$USERNAME"/
wget https://github.com/solarlabsteam/cosmos-exporter/releases/download/v0.2.0/cosmos-exporter_0.2.0_Linux_x86_64.tar.gz
tar xvfz cosmos-exporter_0.2.0_Linux_x86_64.tar.gz

cat >/etc/systemd/system/cosmos-exporter.service <<EOF
[Unit]
Description=Cosmos Exporter
After=network-online.target

[Service]
User=$USERNAME
TimeoutStartSec=0
CPUWeight=95
IOWeight=95
ExecStart=/home/$USERNAME/cosmos-exporter --denom juno --denom-coefficient 1000000 --bech-prefix juno --node $GRPC_URL --tendermint-rpc $TENDERMINT_RPC_URL
Restart=always
RestartSec=2
LimitNOFILE=800000
KillSignal=SIGTERM

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload

systemctl enable node-exporter-prometheus
systemctl enable prometheus
systemctl enable grafana-server

systemctl start node-exporter-prometheus
systemctl start prometheus
systemctl start grafana-server

systemctl enable redis-server
systemctl start redis-server

systemctl enable panic_alerter.service
systemctl start panic_alerter.service

systemctl enable cosmos-exporter
systemctl start cosmos-exporter
