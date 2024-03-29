# Compute the Eigentrust values within your local database
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
DB_SCHEMA=${2:-${DB_SCHEMA:-public}}

if [ -z "${1}" ]; then
  echo "Usage:   $0 [env_name] [db_schema]"
  echo ""
  echo "Example: $0 ${ENV} ${DB_SCHEMA}"
  echo ""
  echo "Params:"
  echo "  [env_name]  The environment to run Eigentrust compute on"
  echo "  [db_schema] The namespace schema to compute Eigentrust strategies on, and the DB schema to store localtrust"
  echo ""
  exit
fi

NPM=$(which npm)

if [ ! -f "${NPM}" ]; then
  echo "Installing NodeJS"
  curl -fsSL https://deb.nodesource.com/setup_18.x | sudo -E bash - &&\
  sudo apt-get install -y nodejs
fi

cd $ENV/ts-lens
export NODE_OPTIONS=--max_old_space_size=6144
yarn install && yarn compute ${DB_SCHEMA}

cd $CWD

echo "Compute process exited. Operation complete!  The Karma3Labs Lens API can now be started to return recommendations"
echo ""
echo "Next up, run: $SCRIPT_DIR/4-startserver.sh"
echo ""
# This will not execute but display the usage, as more params are required
$SCRIPT_DIR/4-startserver.sh
echo ""
