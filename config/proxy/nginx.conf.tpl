events {
  worker_connections 1024;
}

http {
  server {
    listen 80;
    listen [::]:80;
    server_name ${PROJECT_DOMAIN};

    error_log /var/log/nginx/error80.log info;

    return 301 https://$host$request_uri;
  }

  server {
    listen 443 ssl;
    listen [::]:443 ssl;
    server_name ${PROJECT_DOMAIN};

    error_log /var/log/nginx/error443.log info;

    ssl_certificate /etc/nginx/certs/${PROJECT_DOMAIN}.crt;
    ssl_certificate_key /etc/nginx/certs/${PROJECT_DOMAIN}.key;
    ssl_protocols TLSv1 TLSv1.1 TLSv1.2;
    ssl_ciphers HIGH:!aNULL:!MD5;

    location / {
      proxy_buffering off;
      proxy_set_header X-Forwarded-Proto $scheme;
      proxy_set_header X-Forwarded-Host $host;
      proxy_set_header X-Forwarded-Port $server_port;

      proxy_pass ${WORDPRESS_URL};
    }
  }
}