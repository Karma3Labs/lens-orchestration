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
