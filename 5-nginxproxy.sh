# Initialize a new env for Lens and Eigentrust
SCRIPT_DIR=$(dirname "$(readlink -f "$0")")
CWD=$PWD
ENV=${1:-"alpha"}
DOMAIN=${2:-"lens-api.yourdomain.com"}
EMAIL=${3:-"ops-email-for-certbot@yourdomain.com"}


if [ -z "${1}" ]; then
  echo "Usage:   $0 env_name domain_name ops_email"
  echo ""
  echo "Example: $0 ${ENV} ${DOMAIN} ${EMAIL}"
  echo ""
  echo "Params:"
  echo "  [env_name]   The environment to front the Eigentrust port"
  echo "  [api_domain] The domain for this API configured to this server's public IP address $(curl -qs ifconfig.me)"
  echo "  [ops_email]  The email address for Certbot to alert when SSL is near expiration"
  echo ""
  exit
fi

if [ -f "${ENV}/ts-lens/.env" ]; then
  source ${ENV}/ts-lens/.env
else
  echo "Unable to find the environment file ${ENV}/ts-lens/.env"
  exit
fi

if [ -z "${LENS_PORT}" ]; then
  echo "Error: Unable to find the Lens API port"
  exit
fi

sudo apt update
sudo apt -y install nginx certbot python3-certbot-nginx

echo "Configure nginx proxy to point to localhost:${LENS_PORT}"

cat << EOF | sudo tee /etc/nginx/sites-available/k3l-api-${ENV}
server {
    listen 80;
    server_name $DOMAIN;

    location / {
        proxy_pass http://localhost:${LENS_PORT};
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection 'upgrade';
        proxy_set_header Host \$host;
        proxy_cache_bypass \$http_upgrade;
    }
}
EOF

echo "Creating symbolic link to nginx sites-enabled"
sudo ln -s /etc/nginx/sites-available/k3l-api-${ENV} /etc/nginx/sites-enabled/

echo "Test the configuration"
sudo nginx -t

echo "If the configuration test is successful, restart Nginx"
if [ $? -eq 0 ]; then
  sudo systemctl restart nginx
else
  echo "Nginx configuration test failed"
  exit
fi

echo "Success.  Now, installing SSL certificate with Certbot"
sudo certbot --nginx -d ${DOMAIN} -m ${EMAIL} --agree-tos -n

if [ $? -eq 0 ]; then
  echo "Certbot setup succeeded!"
else
  echo "There was an error while setting up Certbot, most likely is due to DNS not configured properly"
  exit
fi

echo ""
echo "The Karma3Labs Lens API is now fronted by nginx and can respond with recommendations securely on https://${DOMAIN}"
echo ""
echo "Sample curl:"
echo ""
echo "  curl -qs \"https://${DOMAIN}/profile_scores?strategy=engagement&limit=5\" | jq"
echo ""
echo "(see docs at karma3labs.com site)"
echo ""
