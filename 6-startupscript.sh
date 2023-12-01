# Create startup scripts so that your service auto restarts on reboot or crashes
SCRIPT_DIR=$(dirname "$(readlink -f "$0")")
CWD=$PWD

if [ -f ".env" ]; then
  source ".env"
fi

if [ -f ".env.${ENV}" ] || [ -f ".env" ]; then
  if [ -f ".env.${ENV}" ]; then
    source ".env.${ENV}"
  fi
  export ENV=${ENV}
  export PROJECT_ID=${PROJECT_ID}
  export REGION_CODE=${REGION_CODE}
  export GCS_BUCKET_NAME=${GCS_BUCKET_NAME}
fi

ENV=${1:-${ENV:-alpha}}

if [ -z "${1}" ]; then
  echo "Usage:   $0 [env_name]"
  echo ""
  echo "Example: $0 ${ENV}"
  echo ""
  echo "Params:"
  echo "  [env_name]  The environment to setup the startup scripts"
  echo ""
  exit
fi

if [ -f "${ENV}/ts-lens/.env" ]; then
  source ${ENV}/ts-lens/.env
else
  echo "Unable to find the environment file ${ENV}/ts-lens/.env"
  exit
fi

echo "Setting up startup script for lens-$ENV.service"
cat << EOF | sudo tee /etc/systemd/system/lens-$ENV.service
[Unit]
Description=Lens $ENV
Requires=docker.service
After=docker.service

[Service]
Restart=on-failure
RestartSec=3
ExecStart=/usr/bin/docker-compose -f /home/ubuntu/orchestration/$ENV/docker-compose.yml up
ExecStop=/usr/bin/docker-compose -f /home/ubuntu/orchestration/$ENV/docker-compose.yml down
User=root
Group=docker
Type=simple

[Install]
WantedBy=default.target
EOF

sudo systemctl daemon-reload
sudo systemctl enable lens-$ENV.service

echo ""
echo "To run services at startup:  sudo systemctl enable lens-$ENV"
echo "To start all services, run:  sudo systemctl start lens-$ENV"
echo "To stop all services, run:   sudo systemctl stop lens-$ENV"
echo ""
echo "Done!"
echo ""
