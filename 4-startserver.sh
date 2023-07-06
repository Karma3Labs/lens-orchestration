# Start the API service to serve your computed dataset
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

ENV=${1:-${ENV:-alpha}}

if [ -z "${1}" ]; then
  echo "Usage:   $0 [env_name]"
  echo ""
  echo "Example: $0 ${ENV}"
  echo ""
  echo "Params:"
  echo "  [env_name]  The environment to run Eigentrust compute on"
  echo ""
  exit
fi

if [ -f "${ENV}/ts-lens/.env" ]; then
  source ${ENV}/ts-lens/.env
else
  echo "Unable to find the environment file ${ENV}/ts-lens/.env"
  exit
fi

EIGENTRUST_IP=$(docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' go-eigentrust-${ENV})
DB_HOST_IP=$(docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' lens-db-${ENV})

# Time to repair and rebuild the ts-lens docker image
sed -i "s/^EIGENTRUST_API=.*/EIGENTRUST_API=http:\/\/${EIGENTRUST_IP}:80/" ${ENV}/ts-lens/.env
sed -i "s/^DB_HOST=.*/DB_HOST=${DB_HOST_IP}/" ${ENV}/ts-lens/.env
sed -i "s/^DB_PORT=.*/DB_PORT=5432/" ${ENV}/ts-lens/.env
rm ${ENV}/.env
ln -s ts-lens/.env ${ENV}/.env

echo "Bringing down ts-lens docker instance and repairing the ts-lens image"
docker stop ts-lens-${ENV}
docker container rm ts-lens-${ENV}
docker image rm ts-lens-${ENV}
cd ${ENV}/ts-lens
docker build -t ts-lens-${ENV} .
cd $CWD
echo "Restarting docker instance"
docker-compose -f ${ENV}/docker-compose.yml up -d ts-lens

echo ""
echo "The Karma3Labs Lens API has started and can respond with recommendations on localhost:${LENS_PORT}"
echo ""
echo "Sample curl:"
echo ""
echo "  curl -qs \"http://localhost:${LENS_PORT}/profile/scores?strategy=engagement&limit=5\" | jq"
echo ""
echo "(see docs at karma3labs.com site)"
echo ""
echo "To inspect the Postgres DB:"
echo ""
echo "  psql -h $DB_HOST -p $DB_PORT -U $DB_USERNAME -d $DB_NAME"
echo ""
echo "(password => $DB_PASSWORD)"
echo ""
