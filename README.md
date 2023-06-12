# Introduction
This repository contains a set of scripts that performs a step-by-step orchestration of walking through developers from start to finish, 
from having no footprint of a Karma3 Labs recommendation engine, to having a full fledged backend API fronted by nginx via SSL with 
the latest Lens dataset computed for profile rankings and content recommendations.

## Prerequisite
- some knowledge of Linux command-line interface
- an Ubuntu server, preferably Ubuntu 20.04+, with at least 4 CPU cores and 16GB RAM
- if running from a home network, you might need to configure your firewall to gain access to your server
- a Google Cloud account with [a project set up](https://cloud.google.com/resource-manager/docs/creating-managing-projects), to retrieve of Lens BigQuery data and export dataset in GCS
- a Google Cloud service account with **BigQuery Admin** and **Storage Admin** in its [IAM policies](https://console.cloud.google.com/iam-admin/iam) for your project
- access to a domain that you can update DNS entries to point a new subdomain to an API service
- an email address to receive Certbot messages when SSL is expiring

# Orchestration

## ./0-cloudinit.sh
To initialize Google Cloud Services with a new bucket name, based on a Project ID that you own.  You will need to create this Project ID
via the [Google Cloud Console](https://developers.google.com/workspace/guides/create-project) before being able to proceed.
```
Usage:   ./0-cloudinit.sh [bucket_name] [project_id] [region_code]

Example: ./0-cloudinit.sh k3l-lens-bq-blue lens-bigquery us-east5

Params:
  [bucket_name]  Your Google Cloud Storage bucket name to store exports of Lens BigQuery dataset during ETL download
  [project_id]   Your Google Cloud Project ID.  To create one, go to https://developers.google.com/workspace/guides/create-project
  [region_code]  Look for your desired GCP region code at https://cloud.google.com/compute/docs/regions-zones
```

## ./1-bootstrap.sh
To bootstrap your local environment's docker, mapped to unused port in your local Ubuntu server to host a compute layer, the API and a Postgres database port.
This process is basically to set up the framework in your server with 3 docker containers for each compute, api and storage layers.
```
Usage:   ./1-bootstrap.sh [env_name] [comp_port] [api_port] [db_port] [db_passwd]

Example: ./1-bootstrap.sh  55581 55561 55541 bf1ed2b37b5a12e9771404a82f03b42c

Params:
  [env_name]  An environment name to use, to name folders and tag docker containers
  [comp_port] The Eigentrust compute port, for the Lens instance to communicate with it
  [api_port]  The ts-lens middleware is also hosting a port on localhost, which can be proxied to external api
  [db_port]   The database port where both the api layer will need to connect to
  [db_passwd] The password for the postgres database admin user
```

## ./2-populate.sh
This is an extensive script to export data as CSV dataset from Lens BigQuery into Google Cloud Services (GCS), then downloading that CSV dataset into
your local server, followed by populating your local Postgres database with the right amount of dataset enough to compute profile rankings and scores.
This process could take about 5-15 mins depending on the throughput of your server
```
Usage:   ./2-populate.sh [env_name] [gcs_bucket]

Example: ./2-populate.sh alpha k3l-lens-staging

Params:
  [env_name]   To run the ETL to populate this environment
  [gcs_bucket] Your designated Google Cloud Storage bucket name
```

## ./3-compute.sh
This is where the magic happens, by running the compute process of EigenTrust on the dataset from Lens BigQuery.  This process could take up to 15 mins.
```
Usage:   ./3-compute.sh [env_name]

Example: ./3-compute.sh alpha

Params:
  [env_name]  The environment to run Eigentrust compute on
```

## ./4-startserver.sh
This starts the API server whilst making a few adjustments to cater for port exposures and Docker environments
```
Usage:   ./4-startserver.sh [env_name]

Example: ./4-startserver.sh alpha

Params:
  [env_name]  The environment to run Eigentrust compute on
```

## ./5-nginxproxy.sh
When you're ready to productionalize the API, this script enables you to create an nginx proxy with the ability to map the local port into an SSL-backed API.
You will need access to a DNS service (such as Cloudflare or AWS Route53) in order to map a fully qualified domain name to the local server's public IP address.
```
Usage:   ./5-nginxproxy.sh env_name domain_name ops_email

Example: ./5-nginxproxy.sh alpha lens-api.yourdomain.com ops-email-for-certbot@yourdomain.com

Params:
  [env_name]   The environment to front the Eigentrust port
  [api_domain] The domain for this API configured to this server's public IP address 65.109.94.216
  [ops_email]  The email address for Certbot to alert when SSL is near expiration
```

## ./6-startupscript.sh
To set up startup scripts on Ubuntu using systemd, this script will set one up for you
```
Usage:   ./6-startupscript.sh [env_name]

Example: ./6-startupscript.sh alpha

Params:
  [env_name]  The environment to setup the startup scripts
```

## ./7-update.sh
When you find the dataset stale, you can run an update to pull in the differential between Lens BigQuery and your local Postgres database using this script
```
Usage:   ./7-update.sh [env_name] [gcs_bucket]

Example: ./7-update.sh  

Params:
  [env_name]   To run the ETL to populate this environment
  [gcs_bucket] Your designated Google Cloud Storage bucket name
```

## ./8-rebuild.sh
If there are any new update to the open sourced codebase from Karma3 Labs, you might wish to rebuild your docker images with this script.
```
Usage:   ./8-rebuild.sh [env_name]

Example: ./8-rebuild.sh alpha

Params:
  [env_name]  The environment tear down
```

## ./9-teardown.sh
If you'd like to cleanup the environment, you can run this script to tear down the entire environment, including docker containers and the database data directories.
```
Usage:   ./9-teardown.sh [env_name]

Example: ./9-teardown.sh alpha

Params:
  [env_name]  The environment tear down
```
