# Initialize a new env for Lens and Eigentrust
GCS_BUCKET_NAME=${1:-"k3l-lens-bq-blue"}
PROJECT_ID=${2:-"lens-bigquery"}
REGION_CODE=${3:-"us-east5"}
SCRIPT_DIR=$(dirname "$(readlink -f "$0")")

if [ -z "${3}" ]; then
  echo "Usage:   $0 [bucket_name] [project_id] [region_code]"
  echo ""
  echo "Example: $0 ${GCS_BUCKET_NAME} ${PROJECT_ID} ${REGION_CODE}"
  echo ""
  echo "Params:"
  echo "  [bucket_name]  Your Google Cloud Storage bucket name to store exports of Lens BigQuery dataset during ETL download"
  echo "  [project_id]   Your Google Cloud Project ID.  To create one, go to https://developers.google.com/workspace/guides/create-project"
  echo "  [region_code]  Look for your desired GCP region code at https://cloud.google.com/compute/docs/regions-zones"
  echo ""
  exit
fi

# Based on steps in here https://cloud.google.com/sdk/docs/install
GSUTIL=$(which gsutil)
if [ ! -f "${GSUTIL}" ]; then
  echo "Installing Google Cloud CLI"
  sudo apt-get install -y apt-transport-https ca-certificates gnupg
  echo "deb [signed-by=/usr/share/keyrings/cloud.google.gpg] https://packages.cloud.google.com/apt cloud-sdk main" | sudo tee -a /etc/apt/sources.list.d/google-cloud-sdk.list
  curl https://packages.cloud.google.com/apt/doc/apt-key.gpg | sudo apt-key --keyring /usr/share/keyrings/cloud.google.gpg add -
  sudo apt-get update && sudo apt-get install -y google-cloud-cli
  gcloud init
else
  echo "Google Cloud CLI may have been installed already"
  gcloud auth list
  read -r -p "Please verify the right GCloud service account is active.  Proceed? [y/N] " response
    case "$response" in
      [yY][eE][sS]|[yY])
          ;;
      *)
          exit
          ;;
    esac
fi

# Creating a bucket, see https://cloud.google.com/storage/docs/creating-buckets#storage-create-bucket-cli
gsutil mb -p "${PROJECT_ID}" -c "STANDARD" -l "${REGION_CODE}" -b on gs://${GCS_BUCKET_NAME}

cat << EOF | tee .env
ENV=
PROJECT_ID="${PROJECT_ID}"
REGION_CODE="${REGION_CODE}"
GCS_BUCKET_NAME="${GCS_BUCKET_NAME}"
EOF

echo "GCS bucket created.  Init complete!"
echo ""
echo "Next up, run: $SCRIPT_DIR/1-bootstrap.sh"
echo ""
# This will not execute but display the usage, as more params are required
$SCRIPT_DIR/1-bootstrap.sh
echo ""
