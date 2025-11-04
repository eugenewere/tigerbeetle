#!/usr/bin/env bash
set -euo pipefail

TB_BIN="/usr/local/bin/tigerbeetle"

if ! command -v tigerbeetle >/dev/null 2>&1; then
  echo "Downloading TigerBeetle binary..."
  curl -Lo /tmp/tigerbeetle.zip https://linux.tigerbeetle.com
  unzip /tmp/tigerbeetle.zip -d /tmp/tigerbeetle
  sudo mv /tmp/tigerbeetle/tigerbeetle ${TB_BIN}
  sudo chmod +x ${TB_BIN}
  echo "TigerBeetle installed at ${TB_BIN}"
else
  echo "TigerBeetle already installed."
fi

tigerbeetle version


ENVIRONMENT="${1:-dev}" # usage: ./install_tb.sh dev|prod

if [[ "$ENVIRONMENT" != "dev" && "$ENVIRONMENT" != "prod" ]]; then
  echo "Usage: $0 [dev|prod]"
  exit 1
fi

# Common config
INSTALL_DIR="/usr/local/bin"
STATE_BASE_DIR="/var/lib/tigerbeetle"
SERVICE_FILE="/etc/systemd/system/tigerbeetle-${ENVIRONMENT}.service"
PRE_START_SCRIPT="/usr/local/bin/tigerbeetle-${ENVIRONMENT}-pre-start.sh"

if [ "$ENVIRONMENT" = "dev" ]; then
  ADDRESSES="3001"
  CLUSTER_ID="0"
  REPLICA_INDEX="0"
  REPLICA_COUNT="1"
  CACHE_GRID_SIZE="2GiB"
else
  ADDRESSES="4001"
  CLUSTER_ID="1"
  REPLICA_INDEX="0"
  REPLICA_COUNT="3"  # adjust for production cluster
  CACHE_GRID_SIZE="2GiB"
fi

STATE_DIR="${STATE_BASE_DIR}/${ENVIRONMENT}"
DATA_FILE="${STATE_DIR}/${CLUSTER_ID}_${REPLICA_INDEX}.tigerbeetle"

# Create dirs
sudo mkdir -p "${STATE_DIR}"
sudo chmod 700 "${STATE_DIR}"

# Write pre-start script
sudo tee ${PRE_START_SCRIPT} > /dev/null <<EOF
#!/bin/sh
set -eu
if ! test -e "${DATA_FILE}"; then
  ${INSTALL_DIR}/tigerbeetle format --cluster="${CLUSTER_ID}" --replica="${REPLICA_INDEX}" --replica-count="${REPLICA_COUNT}" "${DATA_FILE}"
fi
EOF
sudo chmod +x ${PRE_START_SCRIPT}

# Write systemd service
sudo tee ${SERVICE_FILE} > /dev/null <<EOF
[Unit]
Description=TigerBeetle ${ENVIRONMENT^} Replica
After=network-online.target

[Service]
AmbientCapabilities=CAP_IPC_LOCK
Environment=TIGERBEETLE_CACHE_GRID_SIZE=${CACHE_GRID_SIZE}
Environment=TIGERBEETLE_ADDRESSES=${ADDRESSES}
Environment=TIGERBEETLE_REPLICA_COUNT=${REPLICA_COUNT}
Environment=TIGERBEETLE_REPLICA_INDEX=${REPLICA_INDEX}
Environment=TIGERBEETLE_CLUSTER_ID=${CLUSTER_ID}
Environment=TIGERBEETLE_DATA_FILE=${DATA_FILE}
StateDirectory=tigerbeetle/${ENVIRONMENT}
StateDirectoryMode=700
Type=exec
ExecStartPre=${PRE_START_SCRIPT}
ExecStart=/bin/bash -c '/usr/local/bin/tigerbeetle start --cache-grid=${TIGERBEETLE_CACHE_GRID_SIZE} --addresses=${TIGERBEETLE_ADDRESSES} ${TIGERBEETLE_DATA_FILE}'

[Install]
WantedBy=multi-user.target
EOF

sudo systemctl daemon-reload
sudo systemctl enable tigerbeetle-${ENVIRONMENT}.service
sudo systemctl start tigerbeetle-${ENVIRONMENT}.service

echo "✅ TigerBeetle ${ENVIRONMENT} environment installed and started."
