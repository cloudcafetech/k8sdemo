#!/bin/bash
if [ "$#" -lt 0 ]; then
  echo "Usage: $0"
  exit 1
fi

echo "Generating nip.io based on found external IP"
FOUNDIP=172.30.1.2
APIFQDN="minio-api.${FOUNDIP}.nip.io"
FQDN="minio.${FOUNDIP}.nip.io"

echo "Using API FQDN: ${APIFQDN}"
echo "Using Console FQDN: ${FQDN}"

# Minio setup
# Generated access key and secret key
ACCESS_KEY=admin
SECRET_KEY=admin2675

# Generate certificates
mkdir api
cd api
curl https://gist.githubusercontent.com/superseb/b2c1d6c9baa32609a49ee117a27bc700/raw/7cb196e974e13b213ac6ec3105971dd5e21e4c66/selfsignedcert.sh | bash -s -- $APIFQDN
cd ..
mkdir console
cd console
curl https://gist.githubusercontent.com/superseb/b2c1d6c9baa32609a49ee117a27bc700/raw/7cb196e974e13b213ac6ec3105971dd5e21e4c66/selfsignedcert.sh | bash -s -- $FQDN
cd ..

cat $PWD/api/certs/ca.pem > $PWD/public.crt
cat $PWD/console/certs/ca.pem >> $PWD/public.crt

# Run minio container
docker run -d --name=minio -p 9000:9000 -p 9090:9090 -e MINIO_ROOT_USER=$ACCESS_KEY -e MINIO_ROOT_PASSWORD=$SECRET_KEY -e MINIO_SERVER_URL="https://${APIFQDN}" -e MINIO_BROWSER_REDIRECT_URL="https://${FQDN}" -v $PWD/data:/data -v $PWD/public.crt:/root/.minio/certs/CAs/public.crt minio/minio server /data --console-address=:9090

# nginx
cat <<EOF > $PWD/nginx.conf
server {
    listen 80;
    server_name $FQDN;
    return 301 https://$FQDN$request_uri;
}
server {
    listen               443 ssl;
    server_name          $APIFQDN;
    
    # To allow special characters in headers
    ignore_invalid_headers off;
    # Allow any size file to be uploaded.
    # Set to a value such as 1000m; to restrict file size to a specific value
    client_max_body_size 0;
    # To disable buffering
    proxy_buffering off;
     
    ssl_certificate      /apicerts/cert.pem;
    ssl_certificate_key  /apicerts/key.pem;
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256:ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384:ECDHE-ECDSA-CHACHA20-POLY1305:ECDHE-RSA-CHACHA20-POLY1305:DHE-RSA-AES128-GCM-SHA256:DHE-RSA-AES256-GCM-SHA384;
    ssl_prefer_server_ciphers off;
    location / {
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_set_header Host \$http_host;
        
        proxy_connect_timeout 300;
        # Default is HTTP/1, keepalive is only enabled in HTTP/1.1
        proxy_http_version 1.1;
        proxy_set_header Connection "";
        chunked_transfer_encoding off;
        proxy_pass       http://minio:9000;
    }
}
server {
    listen               443 ssl;
    server_name          $FQDN;
    
    # To allow special characters in headers
    ignore_invalid_headers off;
    # Allow any size file to be uploaded.
    # Set to a value such as 1000m; to restrict file size to a specific value
    client_max_body_size 0;
    # To disable buffering
    proxy_buffering off;
     
    ssl_certificate      /consolecerts/cert.pem;
    ssl_certificate_key  /consolecerts/key.pem;
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256:ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384:ECDHE-ECDSA-CHACHA20-POLY1305:ECDHE-RSA-CHACHA20-POLY1305:DHE-RSA-AES128-GCM-SHA256:DHE-RSA-AES256-GCM-SHA384;
    ssl_prefer_server_ciphers off;
    location / {
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_set_header Host \$http_host;
        
        proxy_connect_timeout 300;
        # Default is HTTP/1, keepalive is only enabled in HTTP/1.1
        proxy_http_version 1.1;
        proxy_set_header Connection "";
        chunked_transfer_encoding off;
        proxy_pass       http://minio:9090;
    }
}

EOF

docker run -d --name=nginx -p 80:80 -p 443:443 -v $PWD/nginx.conf:/etc/nginx/conf.d/minio.conf:ro -v $PWD/api/certs:/apicerts -v $PWD/console/certs:/consolecerts --link=minio nginx

mkdir -p $PWD/.mc/certs/CAs
cat $PWD/api/certs/ca.pem > $PWD/.mc/certs/CAs/public.crt
cat $PWD/console/certs/ca.pem >> $PWD/.mc/certs/CAs/public.crt
docker run --rm -v $PWD/.mc:/root/.mc minio/mc config host add minio https://$APIFQDN $ACCESS_KEY $SECRET_KEY
docker run --rm -v $PWD/.mc:/root/.mc minio/mc mb minio/pgbkp

MINIO_FILE=$PWD/minio-info.txt
echo "Minio API URL: $APIFQDN" | tee -a $MINIO_FILE
echo "Minio Console URL: $FQDN" | tee -a $MINIO_FILE
echo "Minio Access Key: $ACCESS_KEY" | tee -a $MINIO_FILE
echo "Minio Secret Key: $SECRET_KEY" | tee -a $MINIO_FILE
echo "Minio created bucket: pgbkp" | tee -a $MINIO_FILE
echo "CA certificate:" | tee -a $MINIO_FILE
cat $PWD/api/certs/ca.pem | tee -a $MINIO_FILE
echo "Using Minio mc: list files in pgbkp" | tee -a $MINIO_FILE
echo "docker run --rm -v \$PWD/.mc:/root/.mc minio/mc ls minio/pgbkp" | tee -a $MINIO_FILE
echo "Using Minio mc: interactive shell" | tee -a $MINIO_FILE
echo "docker run --rm -v \$PWD/.mc:/root/.mc -ti --entrypoint sh minio/mc" | tee -a $MINIO_FILE
echo "All Minio info is also stored in ${MINIO_FILE}"
