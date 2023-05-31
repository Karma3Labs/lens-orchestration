# Initialize a new env for Lens and Eigentrust
SCRIPT_DIR=$(dirname "$(readlink -f "$0")")
CWD=$PWD
if [ -f ".env" ]; then
  source .env
fi
ENV=${1:${ENV:-"alpha"}}
EIGENTRUST_PORT=${2:-55581}
LENS_PORT=${3:-55561}
DB_PORT=${4:-55541}
DB_PASSWORD=${5:-$(openssl rand -hex 16)}

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
  sed -i "s/^ENV=/ENV=${ENV}/" .env
fi

mkdir -p $ENV
git clone https://github.com/karma3labs/go-eigentrust ${ENV}/go-eigentrust
git clone https://github.com/karma3labs/ts-lens ${ENV}/ts-lens
docker pull postgres

# Get the internal IPv4 of the docker0 interface
DOCKER_IFACE=$(ip -4 addr show docker0 | grep -oP '(?<=inet\s)\d+(\.\d+){3}')

cd $ENV

# Default env variable setup
cat << EOF | tee ts-lens/.env
EIGENTRUST_API=http://${DOCKER_IFACE}:${EIGENTRUST_PORT}
GRAPHQL_API=https://api.lens.dev/
DB_HOST=${DOCKER_IFACE}
DB_PORT=${DB_PORT}
DB_USERNAME=postgres
DB_PASSWORD=${DB_PASSWORD}
DB_NAME=lens_bigquery
LENS_PORT=${LENS_PORT}
EOF

# Create a soft link
ln -s ts-lens/.env .env

# Default docker-compose.yml setup
cat << EOF | tee docker-compose.yml
version: '3.8'
services:
  lens_db:
    image: postgres
    user: "998:998"
    container_name: lens-db-${ENV}
    restart: always
    shm_size: 512MB
    ports:
      - ${DB_PORT}:5432
    volumes:
      - /var/lib/postgresql/data:/var/lib/postgresql/data
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
docker build ${CWD}/${ENV}/go-eigentrust/. -t go-eigentrust-${ENV}
docker build ${CWD}/${ENV}/ts-lens/. -t ts-lens-${ENV}

cd $CWD

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
