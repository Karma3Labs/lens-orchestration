# Initialize a new env for Lens and Eigentrust
CWD=$PWD
DEFAULT_ENV=alpha
ENV=${1:-$DEFAULT_ENV}

if [ -z "${1}" ]; then
  echo "Usage:   $0 [env_name]"
  echo ""
  echo "Example: $0 ${ENV}"
  echo ""
  echo "Params:"
  echo "  [env_name]  The environment tear down"
  echo ""
  exit
fi

if [ ! -d "${ENV}" ]; then
  echo "Environment or folder called \"${ENV}\" does not exist!"
  exit
fi

read -r -p "Shutdown docker instances for \"${ENV}\" and rebuild docker images? [y/N] " response
case "$response" in
    [yY][eE][sS]|[yY])
        ;;
    *)
        exit
        ;;
esac

echo "Bringing down the environments"
docker-compose -f ${ENV}/docker-compose.yml down
echo "Cleaning up docker images"
docker image rm ts-lens-${ENV}
docker image rm go-eigentrust-${ENV}
docker image rm lens-db-${ENV}

cd ${ENV}/go-eigentrust
git fetch && git pull
cd $CWD

cd ${ENV}/ts-lens
git fetch && git pull
docker pull postgres

cd $CWD

# Build new images
docker build ${CWD}/${ENV}/go-eigentrust/. -t go-eigentrust-${ENV}
docker build ${CWD}/${ENV}/ts-lens/. -t ts-lens-${ENV}

docker-compose -f ${ENV}/docker-compose.yml up -d


echo "Environment ${ENV} is ready"
echo ""
echo "   To start:   docker-compose -f ${ENV}/docker-compose.yml up -d  (started)"
echo "   To stop:    docker-compose -f ${ENV}/docker-compose.yml down"
echo ""
echo "Started via docker-compose up.  Docker rebuild complete."
echo ""
echo "Next up, run: $SCRIPT_DIR/4-startserver.sh"
echo ""
# This will not execute but display the usage, as more params are required
$SCRIPT_DIR/4-startserver.sh
echo ""
