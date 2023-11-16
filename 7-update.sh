# Update your local database with the most recent data from Lens BigQuery
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
GCS_BUCKET_NAME=${2:-${GCS_BUCKET_NAME:-"k3l-lens-v2-alpha"}}
IS_FULL=${3}

if [ -z "${2}" ]; then
  echo "Usage:   $0 [env_name] [gcs_bucket] [refresh]"
  echo ""
  echo "Example: $0 $ENV $GCS_BUCKET_NAME"
  echo "Example: $0 $ENV $GCS_BUCKET_NAME refresh"
  echo ""
  echo "Params:"
  echo "  [env_name]   To run the ETL to populate this environment"
  echo "  [gcs_bucket] Your designated Google Cloud Storage bucket name"
  echo "  [refresh]    Refresh the entire database (this is optional and costlier)"
  echo ""
  exit
fi

cd $ENV
LENS_ENV=ts-lens/.env
if [ ! -f "$LENS_ENV" ]; then
  echo "Missing Lens .env environment file"
  exit
fi

source $LENS_ENV

DB_USER=${DB_USERNAME}

REPO=lens-etl
if [ ! -d "$REPO" ]; then
  git clone https://github.com/karma3labs/$REPO.git $REPO
else
  cd $REPO
  git pull
  cd ../
fi

# Setup .pgpass to avoid psql from prompting for a password
pgpass="$HOME/.pgpass"
touch $pgpass
chmod 755 $pgpass

# Remove the line with the matching hostname and port using sed in-place edit (-i) and add the new entry
sed -i "/^$DB_HOST:$DB_PORT:/d" $pgpass
echo "$DB_HOST:$DB_PORT:*:$DB_USER:$DB_PASSWORD" >> $pgpass
chmod 600 $pgpass

export WORK_DIR=$CWD/$ENV/$REPO
export GCS_BUCKET_NAME=$GCS_BUCKET_NAME
export DB_HOST=$DB_HOST
export DB_PORT=$DB_PORT
export DB_USER=$DB_USER
export DB_NAME=$DB_NAME
echo "WORK_DIR=$WORK_DIR"
echo "GCS_BUCKET_NAME=$GCS_BUCKET_NAME"

if [ -n "$3" ] && [ "$3" = "refresh" ]; then
  echo "Refreshing entire dataset"
  $WORK_DIR/run-etl-full.sh
else
  echo "Getting the latest updates"
  $WORK_DIR/run-etl-update.sh
fi

# Refresh the views necessary for compute
/usr/bin/psql -e -h $DB_HOST -p $DB_PORT -U $DB_USER -d $DB_NAME -f lens-etl/refresh_materialized_view.sql

echo "Environment ${ENV} is updated.  Time to run compute once more."
