# Initialize a new env for Lens and Eigentrust
SCRIPT_DIR=$(dirname "$(readlink -f "$0")")
CWD=$PWD

if [ -f ".env" ]; then
  source .env
  export ENV=$ENV
fi

ENV=${1:-${ENV:-alpha}}
GCS_BUCKET_NAME=${2:-${GCS_BUCKET_NAME:-"k3l-lens-bigquery-alpha"}}

if [ -z "${2}" ]; then
  echo "Usage:   $0 [env_name] [gcs_bucket]"
  echo ""
  echo "Example: $0 $ENV $GCS_BUCKET_NAME"
  echo ""
  echo "Params:"
  echo "  [env_name]   To run the ETL to populate this environment"
  echo "  [gcs_bucket] Your designated Google Cloud Storage bucket name"
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
fi

# Setup .pgpass to avoid psql from prompting for a password
pgpass="$HOME/.pgpass"
touch $pgpass
chmod 755 $pgpass

# Remove the line with the matching hostname and port using sed in-place edit (-i) and add the new entry
sed -i "/^$DB_HOST:$DB_PORT:/d" $pgpass
echo "$DB_HOST:$DB_PORT:*:$DB_USER:$DB_PASSWORD" >> $pgpass
chmod 600 $pgpass

# Setup the schema
/usr/bin/psql -h $DB_HOST -p $DB_PORT -U $DB_USER -c "CREATE DATABASE ${DB_NAME};"
/usr/bin/psql -h $DB_HOST -p $DB_PORT -U $DB_USER -d $DB_NAME -f lens-etl/lens_bigquery_schema.sql

export WORK_DIR=$CWD/$REPO
export GCS_BUCKET_NAME=$GCS_BUCKET_NAME
export DB_HOST=$DB_HOST
export DB_PORT=$DB_PORT
export DB_USER=$DB_USER
export DB_NAME=$DB_NAME

echo "WORK_DIR=$WORK_DIR"
echo "GCS_BUCKET_NAME=$GCS_BUCKET_NAME"
echo ""
echo "Running the ETL script, it performs the following"
echo "  1) exports several Lens BigQuery tables into GCS as CSVs,"
echo "  2) downloads from GCS to this local machine, and"
echo "  3) imports from the downloaded CSVs into the DB in ${ENV}"
echo ""
echo "Process can take up to 10 mins, depending on the number of tables requested, and the size of each table"
echo ""
echo "To view your GCS bucket, go to https://console.cloud.google.com/storage/browser/${GCS_BUCKET_NAME}"
echo ""
$WORK_DIR/run-etl-full.sh

# Refresh the views necessary for compute
/usr/bin/psql -h $DB_HOST -p $DB_PORT -U $DB_USER -d $DB_NAME -f lens-etl/refresh_materialized_view.sql

echo "Database is populated for the \"${ENV}\" environment"
echo ""
echo "Usage:"
echo "  psql -h $DB_HOST -p $DB_PORT -U $DB_USER -d $DB_NAME"
echo ""
echo "Next up, run: ${SCRIPT_DIR}/3-compute.sh"
echo ""
# This will not execute but display the usage, as more params are required
$SCRIPT_DIR/3-compute.sh
echo ""
