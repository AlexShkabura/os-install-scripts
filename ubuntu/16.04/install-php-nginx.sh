#!/bin/sh

# Get public IP for this server
publicip="$(dig +short myip.opendns.com @resolver1.opendns.com)"

sudo apt-get update && sudo apt-get -y upgrade
sudo apt-get install nano git -y
sudo apt-get install sqlite3 libsqlite3-dev -y

# Install nginx: https://docs.microsoft.com/en-us/aspnet/core/publishing/linuxproduction?tabs=aspnetcore2x
sudo apt-get install nginx -y
sudo service nginx start

# Install php and relevant extensions
sudo apt-get -y install php-fpm php-cli php-json php-zip php-curl php-gd php-common php-sqlite3 php-mysql
sudo apt-get -y install php-finfo

# Set the PHP memory limit to 128MB
sudo sed -i "s/memory_limit = .*/memory_limit = 128MB/" /etc/php/7.0/fpm/php.ini

# Set fix_pathinfo to 0
sudo sed -i "s/;cgi.fix_pathinfo=1/cgi.fix_pathinfo=0/" /etc/php/7.0/fpm/php.ini

# Set the timezone to your local timezone
sudo sed -i "s/;date.timezone.*/date.timezone = UTC/" /etc/php/7.0/fpm/php.ini

# Change the values of upload_max_filesize and post_max_size to 100M
sudo sed -i "s/upload_max_filesize = .*/upload_max_filesize = 100M/" /etc/php/7.0/fpm/php.ini
sudo sed -i "s/post_max_size = .*/post_max_size = 100M/" /etc/php/7.0/fpm/php.ini

sudo service php7.0-fpm restart
# OR, sudo systemctl restart php7.0-fpm

# GO FURTHER, add a self-signed cert with 443 and SSL (works with cloudflare)

# create a self-signed certificate
# see: https://www.digitalocean.com/community/tutorials/how-to-create-a-self-signed-ssl-certificate-for-nginx-in-ubuntu-16-04

sudo openssl req -x509 -nodes -days 365 -newkey rsa:2048 -keyout /etc/ssl/private/nginx-selfsigned.key -out /etc/ssl/certs/nginx-selfsigned.crt -subj /C=US/ST=Illinois/L=Chicago/O=Startup/CN=$publicip
sudo openssl dhparam -out /etc/ssl/certs/dhparam.pem 2048 > /dev/null 2>&1

cat >/etc/nginx/snippets/self-signed.conf <<EOL
ssl_certificate /etc/ssl/certs/nginx-selfsigned.crt;
ssl_certificate_key /etc/ssl/private/nginx-selfsigned.key;
EOL

cat >/etc/nginx/snippets/ssl-params.conf <<EOL
# from https://cipherli.st/
# and https://raymii.org/s/tutorials/Strong_SSL_Security_On_nginx.html
ssl_protocols TLSv1 TLSv1.1 TLSv1.2;
ssl_prefer_server_ciphers on;
ssl_ciphers "EECDH+AESGCM:EDH+AESGCM:AES256+EECDH:AES256+EDH";
ssl_ecdh_curve secp384r1;
ssl_session_cache shared:SSL:10m;
ssl_session_tickets off;
ssl_stapling on;
ssl_stapling_verify on;
resolver 8.8.8.8 8.8.4.4 valid=300s;
resolver_timeout 5s;
# Disable preloading HSTS for now.  You can use the commented out header line that includes
# the "preload" directive if you understand the implications.
#add_header Strict-Transport-Security "max-age=63072000; includeSubdomains; preload";
add_header Strict-Transport-Security "max-age=63072000; includeSubdomains";
add_header X-Frame-Options DENY;
add_header X-Content-Type-Options nosniff;
ssl_dhparam /etc/ssl/certs/dhparam.pem;
EOL

# Before we go any further, let's back up our current server block file:
sudo cp /etc/nginx/sites-available/default /etc/nginx/sites-available/default.bak

# Configure nginx to use php
# sudo nano /etc/nginx/sites-available/default

cat >/etc/nginx/sites-available/default <<EOL
server {
    # SSL configuration
    listen 80 default_server;
    listen [::]:80 default_server;
    listen 443 ssl http2 default_server;
    listen [::]:443 ssl http2 default_server;

    root /var/www/html;
    index index.php index.html index.htm index.nginx-debian.html;

    server_name $publicip;

    include snippets/self-signed.conf;
    include snippets/ssl-params.conf;

    location / {
        # try_files \$uri \$uri/ =404;
        # enable mod_rewrite
        try_files \$uri \$uri/ /index.php?\$args;
    }

    location ~ \.php\$ {
        include snippets/fastcgi-php.conf;
        fastcgi_pass unix:/run/php/php7.0-fpm.sock;
    }

    location ~ /\.ht {
        deny all;
    }
}
EOL

# restart nginx
sudo systemctl reload nginx
#sudo systemctl restart nginx

# create an info.php file
cat >/var/www/html/info.php <<EOL
<?php
phpinfo();

EOL

# setup firewall
sudo apt-get install ufw
sudo ufw default deny incoming
sudo ufw default allow outgoing
sudo ufw allow OpenSSH
sudo ufw allow 'Nginx HTTP'
sudo ufw allow 'Nginx HTTPS'
sudo ufw --force enable
