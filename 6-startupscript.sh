# Initialize a new env for Lens and Eigentrust
SCRIPT_DIR=$(dirname "$(readlink -f "$0")")
CWD=$PWD
DEFAULT_ENV=alpha
ENV=${1:-$DEFAULT_ENV}

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

echo ""
echo "To run services at startup:  sudo systemctl enable lens-$ENV"
echo "To start all services, run:  sudo systemctl start lens-$ENV"
echo "To stop all services, run:   sudo systemctl stop lens-$ENV"
echo ""
echo "Done!"
echo ""
