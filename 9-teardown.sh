# Tear down your services and all docker images
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
GCS_BUCKET_NAME=${2:-${GCS_BUCKET_NAME:-"k3l-lens-bigquery-alpha"}}

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

read -r -p "Are you sure? [y/N] " response
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

DB_DIR=$(grep PGDATA ${ENV}/docker-compose.yml |awk {'print $2'})
if [ ! -z "$DB_DIR" ]; then
  echo "Cleaning up database files"
  sudo rm -fr $DB_DIR
fi

source ${ENV}/ts-lens/.env
if [ ! -z "$GCS_BUCKET_NAME" ]; then
  echo "Removing files from GCS and emptying the bucket ${GCS_BUCKET_NAME}"
  /usr/bin/gsutil -m rm -r "gs://${GCS_BUCKET_NAME}"
fi

rm -fr ${ENV}

echo "Environment ${ENV} tear down completed!"
