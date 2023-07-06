# Bootstrap your environment
SCRIPT_DIR=$(dirname "$(readlink -f "$0")")
CWD=$PWD

if [ -f ".env" ]; then
  source .env
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

# Check if OpenSSL is available
if ! command -v openssl >/dev/null 2>&1; then
  echo "OpenSSL is not found. Installing..."
  sudo apt-get update
  sudo apt-get install -y openssl
  echo "OpenSSL has been installed."
fi

# Check if psql is installed
if ! command -v psql >/dev/null 2>&1; then
  echo "psql is not found. Installing..."
  sudo apt-get update
  sudo apt-get install -y postgresql-client
  echo "psql has been installed."
fi

# Check if git is installed
if ! command -v git >/dev/null 2>&1; then
  echo "Git is not found. Installing..."
  sudo apt-get update
  sudo apt-get install -y git
  echo "Git has been installed."
fi

# Check if Docker is installed
if ! command -v docker >/dev/null 2>&1; then
  echo "Docker is not found. Installing..."
  sudo apt-get update
  sudo apt-get install -y apt-transport-https ca-certificates curl software-properties-common
  curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg
  echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list >/dev/null
  sudo apt-get update
  sudo apt-get install -y docker-ce docker-ce-cli containerd.io
  echo "Docker has been installed."
fi

# Check if Docker is running
if ! systemctl is-active --quiet docker; then
  echo "Docker is not running. Starting Docker..."
  sudo systemctl start docker
  echo "Docker has been started."
fi

# Check if docker-compose is installed
if ! command -v docker-compose >/dev/null 2>&1; then
  echo "docker-compose is not found. Installing..."
  # Download the latest stable release of docker-compose
  sudo curl -L "https://github.com/docker/compose/releases/latest/download/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
  # Apply executable permissions
  sudo chmod +x /usr/local/bin/docker-compose
  echo "docker-compose has been installed."
fi

ENV=${1:-${ENV:-"alpha"}}
EIGENTRUST_PORT=${2:-55581}
LENS_PORT=${3:-55561}
DB_PORT=${4:-55541}
DB_PASSWORD=${5:-$(openssl rand -hex 16)}
DB_USERNAME=postgres
DB_DATA_DIR=/var/lib/postgresql/data
RELEASE_TAG="v1.0"

if [ -z "${5}" ]; then
  echo "Usage:   $0 [env_name] [comp_port] [api_port] [db_port] [db_passwd]"
  echo ""
  echo "Example: $0 $ENV $EIGENTRUST_PORT $LENS_PORT $DB_PORT $DB_PASSWORD"
  echo ""
  echo "Params:"
  echo "  [env_name]  An environment name to use, to name folders and tag docker containers"
  echo "  [comp_port] The Eigentrust compute port, for the Lens instance to communicate with it"
  echo "  [api_port]  The ts-lens middleware is also hosting a port on localhost, which can be proxied to external api"
  echo "  [db_port]   The database port where both the api layer will need to connect to"
  echo "  [db_passwd] The password for the postgres database admin user"
  echo ""
  exit
fi

if [ -f ".env" ]; then
  sed -i "s/^ENV=.*/ENV=${ENV}/" .env
fi

# Check if the current user has sudo privileges for Docker
if sudo -n docker info >/dev/null 2>&1; then
  echo "User has sudo privileges for Docker."
else
  echo "User does not have sudo privileges for Docker. Adding sudo privileges"
  sudo groupadd docker
  sudo usermod -aG docker $USER
  newgrp docker
fi

mkdir -p $ENV

# Retrieve repositories for compute and api layers
git clone https://github.com/karma3labs/go-eigentrust ${ENV}/go-eigentrust
git clone https://github.com/karma3labs/ts-lens ${ENV}/ts-lens

# Make sure we're in the stable versions
cd ${ENV}/go-eigentrust
git fetch --tags
git checkout -b $RELEASE_TAG $RELEASE_TAG
cd ${CWD}

cd ${ENV}/ts-lens
git fetch --tags
git checkout -b $RELEASE_TAG $RELEASE_TAG
cd ${CWD}

# Pull the latest postgres build from docker
docker pull postgres

cd $ENV

# Get the internal IPv4 of the docker0 interface
DOCKER_IFACE=$(ip -4 addr show docker0 | grep -oP '(?<=inet\s)\d+(\.\d+){3}')

# Default env variable setup
cat << EOF | tee ts-lens/.env
EIGENTRUST_API=http://${DOCKER_IFACE}:${EIGENTRUST_PORT}
GRAPHQL_API=https://api.lens.dev/
DB_HOST=${DOCKER_IFACE}
DB_PORT=${DB_PORT}
DB_USERNAME=${DB_USERNAME}
DB_PASSWORD=${DB_PASSWORD}
DB_NAME=lens_bigquery
LENS_PORT=${LENS_PORT}
EOF

# Create a soft link
ln -s ts-lens/.env .env

# Check if the postgres user exists
if id -u ${DB_USERNAME} >/dev/null 2>&1; then
  echo "${DB_USERNAME} user already exists."
else
  echo "Creating ${DB_USERNAME} user..."
  # Create the postgres user without a home directory and disabled password
  sudo useradd --no-create-home --system --shell --disabled-password /bin/bash ${DB_USERNAME}
  echo "User ${DB_USERNAME} user has been created."
fi

# Create a directory and assign ownership to the postgres user
sudo mkdir -p $DB_DATA_DIR
sudo chown ${DB_USERNAME}: $DB_DATA_DIR

echo "Directory created and ownership assigned to postgres user."

# Get the UID and GID for postgres
POSTGRES_UIDGID=`grep ${DB_USERNAME} /etc/passwd | awk -F[:] '{print $3":"$4}'`

echo "Setting up docker-compose.yml"
# Default docker-compose.yml setup
cat << EOF | tee docker-compose.yml
version: '3.8'
services:
  lens_db:
    image: postgres
    user: "$POSTGRES_UIDGID"
    container_name: lens-db-${ENV}
    restart: always
    shm_size: 512MB
    ports:
      - ${DB_PORT}:5432
    volumes:
      - ${DB_DATA_DIR}:/var/lib/postgresql/data
    environment:
      POSTGRES_PASSWORD: ${DB_PASSWORD}
      POSTGRES_DB: lens_db
      PGDATA: /var/lib/postgresql/data/lens_db_${ENV}
    command: -c shared_buffers=20GB -c max_connections=500
    networks:
      - lens_network
  ts-lens:
    container_name: ts-lens-${ENV}
    image: ts-lens-${ENV}:latest
    ports:
      - ${LENS_PORT}:8080
    networks:
      - lens_network
  go-eigentrust:
    container_name: go-eigentrust-${ENV}
    image: go-eigentrust-${ENV}:latest
    ports:
      - ${EIGENTRUST_PORT}:80
    networks:
      - lens_network
networks:
  lens_network:
    driver: bridge
EOF

# Build the initial images
echo "Building docker image go-eigentrust-${ENV}"
docker build ${CWD}/${ENV}/go-eigentrust/. -t go-eigentrust-${ENV}

echo "Building docker image ts-lens-${ENV}"
docker build ${CWD}/${ENV}/ts-lens/. -t ts-lens-${ENV}

cd $CWD

echo "Executing docker-compose \"up\" detached..."
docker-compose -f ${ENV}/docker-compose.yml up -d


echo "Environment ${ENV} is ready"
echo ""
echo "   To start:   docker-compose -f ${ENV}/docker-compose.yml up -d  (started)"
echo "   To stop:    docker-compose -f ${ENV}/docker-compose.yml down"
echo ""
echo "Started via docker-compose up.  Bootstrap complete with a blank slate."
echo ""
echo "Next up, run ${SCRIPT_DIR}/2-populate.sh"
echo ""
# This will not execute but display the usage, as more params are required
$SCRIPT_DIR/2-populate.sh
echo ""
