# Initialize a new env for Lens and Eigentrust
CWD=$PWD
ENV=${1}
GCS_BUCKET_NAME=${2}

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

export WORK_DIR=$CWD/$REPO
export GCS_BUCKET_NAME=$GCS_BUCKET_NAME
export DB_HOST=$DB_HOST
export DB_PORT=$DB_PORT
export DB_USER=$DB_USER
export DB_NAME=$DB_NAME
echo "WORK_DIR=$WORK_DIR"
echo "GCS_BUCKET_NAME=$GCS_BUCKET_NAME"
$WORK_DIR/run-etl-update.sh

# Refresh the views necessary for compute
/usr/bin/psql -h $DB_HOST -p $DB_PORT -U $DB_USER -d $DB_NAME -f lens-etl/refresh_materialized_view.sql

echo "Environment ${ENV} is updated.  Time to run compute once more."
