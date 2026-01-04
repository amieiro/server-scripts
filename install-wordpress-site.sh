#!/bin/bash

# This script install a WordPress in a LAMP environment: Debian, Apache2, 
# MySQL and PHP-FPM

NEW_MYSQL_DATABASE='my_database'                                                        # MySQL database to create
NEW_MYSQL_USERNAME="my_username"                                                        # MySQL username to create
NEW_MYSQL_PASSWORD=`openssl rand --base64 32`                                           # Password for this MySQL user                              
MYSQL_ADMIN_USERNAME="homestead"                                                        # Local MySQL admin username
MYSQL_ADMIN_PASSWORD="secret"                                                           # Local MySQL admin password
NEW_USERNAME="new_username"                                                             # Local username to create
NEW_PASSWORD=`openssl rand --base64 32`                                                 # Password for this local user
NEW_PATH="/var/www/$NEW_USERNAME/wordpress/"                                             # Full path for the website
WEBSITE_NAME="www.example.com"                                                          # Website name
NEW_WORDPRESS_LOCALE="es_ES"                                                            # Locale for the WordPress instalation
NEW_WORDPRESS_URL="$WEBSITE_NAME"                                                       # URL to use in the WordPress instalation
NEW_WORDPRESS_TITLE="My new website"                                                    # Title to use in the WordPress instalation
NEW_WORDPRESS_ADMIN_USERNAME="My_new_WP_user"                                           # Admin user that will be created in the WordPress instalation
NEW_WORDPRESS_ADMIN_PASSWORD=`openssl rand --base64 32`                                 # Password for this WordPress admin user
NEW_WORDPRESS_ADMIN_EMAIL="info@example.com"                                            # Email for this WordPress admin user
PHP_FPM_VERSION="7.4"                                                                   # PHP-FPM version
PHP_FPM_MEMORY_LIMIT="256M"                                                             # PHP-FPM memory limit (PHP-FPM parameter)
SERVERNAME="$WEBSITE_NAME"                                                              # Servername (Apache parameter)
SERVERALIAS="example.com subdomain.example.com"                                         # Serveralias (Apache parameter)
ADD_SSL_TO_APACHE_VIRTUALHOST="yes"                                                     # Do you want to add an SSL certificate to the website? Use "yes" or "no"
CERT_BINARY_FULL_PATH="/usr/bin/certbotxxx"                                             # Full path for the certbot binary. In old versions it is called "certbot-auto"

# Screen colors
# https://stackoverflow.com/questions/5947742/how-to-change-the-output-color-of-echo-in-linux
GREEN='\033[0;32m'
NC='\033[0m' # No Color
RED='\033[0;31m'
YELLOW='\033[0;33m'

function command_exists () {
    command -v $1 >/dev/null 2>&1;
}

function check_if_the_user_is_sudo {
    if [ ${EUID:-$(id -u)} -ne 0 ]; then
        echo -e "${RED}This script must be executed as root ${NC}"
        exit
    fi 
}

function check_if_wp_cli_is_installed {
    if ! command_exists wp; then
            echo "You must have the WP-CLI installed. Please, check https://wp-cli.org"
            exit
    fi
}

function create_new_user {
    echo -e "\n${YELLOW}Creating the new user ${NC}" 
    adduser --disabled-login --system --group --shell=/bin/false $NEW_USERNAME
    echo -e "${GREEN}User created ${NC}\n"
}

function create_database {
    echo -e "\n${YELLOW}Creating the MySQL database: $NEW_MYSQL_DATABASE ${NC}" 
    mysql --user="$MYSQL_ADMIN_USERNAME" --password="$MYSQL_ADMIN_PASSWORD" -e "CREATE DATABASE $NEW_MYSQL_DATABASE CHARACTER SET utf8 COLLATE utf8_general_ci;" 
    echo -e "${GREEN}Database created ${NC}\n" 
    echo -e "\n${YELLOW}Creating the MySQL user: $NEW_MYSQL_USERNAME ${NC}" 
    mysql --user="$MYSQL_ADMIN_USERNAME" --password="$MYSQL_ADMIN_PASSWORD" -e "CREATE USER '$NEW_MYSQL_USERNAME'@'localhost' identified by '$NEW_MYSQL_PASSWORD';" 
    echo -e "${GREEN} Password created for the $NEW_MYSQL_USERNAME user: $NEW_MYSQL_PASSWORD ${NC}\n" 
    echo -e "\n${YELLOW}Granting all privileges on $NEW_MYSQL_DATABASE to '$NEW_MYSQL_USERNAME'@'localhost' ${NC}" 
    mysql --user="$MYSQL_ADMIN_USERNAME" --password="$MYSQL_ADMIN_PASSWORD" -e "GRANT ALL PRIVILEGES ON $NEW_MYSQL_DATABASE.* TO $NEW_MYSQL_USERNAME@localhost;" 
    mysql --user="$MYSQL_ADMIN_USERNAME" --password="$MYSQL_ADMIN_PASSWORD" -e "FLUSH PRIVILEGES;" 
    echo -e "${GREEN}Privileges granted ${NC}\n" 
}

function create_folder_for_website {
    echo -e "\n${YELLOW}Creating the folder for the website: $NEW_PATH ${NC}" 
    rm $NEW_PATH -rf # todo: borrar
    mkdir -p $NEW_PATH
    echo -e "${GREEN}Folder created ${NC}\n" 
}

function install_wordpress {
    echo -e "${YELLOW}Downloading the WordPress core ${NC}" 
    wp core download --path="$NEW_PATH" --allow-root
    echo -e "${GREEN}WordPress core downloaded ${NC}\n" 
    echo -e "${YELLOW}Creating the wp-config.php file ${NC}" 
    wp config create --dbname="$NEW_MYSQL_DATABASE" --dbuser="$NEW_MYSQL_USERNAME" --dbpass="$NEW_MYSQL_PASSWORD" --locale="$NEW_WORDPRESS_LOCALE" --path="$NEW_PATH" --allow-root
    echo -e "${GREEN}wp-config.php file created ${NC}\n" 
    echo -e "${YELLOW}Installing WordPress ${NC}" 
    wp core install --url="http://$NEW_WORDPRESS_URL" --title="$NEW_WORDPRESS_TITLE" --admin_user="$NEW_WORDPRESS_USERNAME" --admin_password="$NEW_WORDPRESS_ADMIN_PASSWORD" --admin_email="$NEW_WORDPRESS_ADMIN_EMAIL"  --path="$NEW_PATH" --allow-root
    echo -e "${GREEN}WordPress installed. Password created for the $NEW_WORDPRESS_USERNAME user: $NEW_WORDPRESS_ADMIN_PASSWORD ${NC}\n" 
}

function update_propietary_and_permissions {
    echo -e "${YELLOW}Changing the propietary of the files in: $NEW_PATH. The new propietary is: $NEW_USERNAME ${NC}" 
    chown $NEW_USERNAME:$NEW_USERNAME $NEW_PATH -R
    echo -e "${GREEN}Propietary changed ${NC}\n" 
    echo -e "${YELLOW}Changing the permissions of the files ${NC}" 
    find $NEW_PATH -type d -exec chmod 755 {} \;
    find $NEW_PATH -type f -exec chmod 644 {} \;
    echo -e "${GREEN}Permissions changed ${NC}\n" 
}

function create_php_fpm_file {
    echo -e "${YELLOW}Creating the PHP-FPM file: /etc/php/$PHP_FPM_VERSION/fpm/pool.d/$SERVERNAME.conf ${NC}" 
    echo "[$NEW_USERNAME]" > /etc/php/$PHP_FPM_VERSION/fpm/pool.d/$SERVERNAME.conf
    echo "user = $NEW_USERNAME" >> /etc/php/$PHP_FPM_VERSION/fpm/pool.d/$SERVERNAME.conf
    echo "group = $NEW_USERNAME" >> /etc/php/$PHP_FPM_VERSION/fpm/pool.d/$SERVERNAME.conf
    echo "" >> /etc/php/$PHP_FPM_VERSION/fpm/pool.d/$SERVERNAME.conf
    echo "listen = /run/php/php$PHP_FPM_VERSION-fpm-$WEBSITE_NAME.sock" >> /etc/php/$PHP_FPM_VERSION/fpm/pool.d/$SERVERNAME.conf
    echo "listen.owner = www-data" >> /etc/php/$PHP_FPM_VERSION/fpm/pool.d/$SERVERNAME.conf
    echo "listen.group = www-data" >> /etc/php/$PHP_FPM_VERSION/fpm/pool.d/$SERVERNAME.conf 
    echo "pm = dynamic" >> /etc/php/$PHP_FPM_VERSION/fpm/pool.d/$SERVERNAME.conf
    echo "" >> /etc/php/$PHP_FPM_VERSION/fpm/pool.d/$SERVERNAME.conf
    echo "pm.max_children = 5" >> /etc/php/$PHP_FPM_VERSION/fpm/pool.d/$SERVERNAME.conf
    echo "pm.start_servers = 2" >> /etc/php/$PHP_FPM_VERSION/fpm/pool.d/$SERVERNAME.conf
    echo "pm.min_spare_servers = 1" >> /etc/php/$PHP_FPM_VERSION/fpm/pool.d/$SERVERNAME.conf
    echo "pm.max_spare_servers = 3" >> /etc/php/$PHP_FPM_VERSION/fpm/pool.d/$SERVERNAME.conf
    echo "php_admin_flag[log_errors] = on" >> /etc/php/$PHP_FPM_VERSION/fpm/pool.d/$SERVERNAME.conf
    echo "catch_workers_output = yes" >> /etc/php/$PHP_FPM_VERSION/fpm/pool.d/$SERVERNAME.conf
    echo "php_admin_value[memory_limit] = $PHP_FPM_MEMORY_LIMIT" >> /etc/php/$PHP_FPM_VERSION/fpm/pool.d/$SERVERNAME.conf
    echo "" >> /etc/php/$PHP_FPM_VERSION/fpm/pool.d/$SERVERNAME.conf
    # echo "php_admin_value[max_execution_time] = 20" >> /etc/php/$PHP_FPM_VERSION/fpm/pool.d/$SERVERNAME.conf
    # echo "php_admin_value[post_max_size] = 18M" >> /etc/php/$PHP_FPM_VERSION/fpm/pool.d/$SERVERNAME.conf
    # echo "php_admin_value[upload_max_filesize] = 16M" >> /etc/php/$PHP_FPM_VERSION/fpm/pool.d/$SERVERNAME.conf
    echo -e "${GREEN}File created ${NC}\n" 
}

function restart_php_fpm_service {
    echo -e "${YELLOW}Restarting the PHP-FPM $PHP_FPM_VERSION service ${NC}" 
    systemctl reload php$PHP_FPM_VERSION-fpm
    systemctl status php$PHP_FPM_VERSION-fpm --no-pager
    echo -e "${GREEN}Service restarted ${NC}\n"
}

function create_apache_virtualhost {
    echo -e "${YELLOW}Creating the Apache virtualhost file: /etc/apache2/sites-available/$SERVERNAME.conf ${NC}" 
    echo "<VirtualHost *:80>" > /etc/apache2/sites-available/$SERVERNAME.conf
    echo "        DocumentRoot $NEW_PATH" >> /etc/apache2/sites-available/$SERVERNAME.conf
    echo "        ServerName $SERVERNAME" >> /etc/apache2/sites-available/$SERVERNAME.conf
    if [ -n "$SERVERALIAS" ]; then
        echo "        ServerAlias $SERVERALIAS" >> /etc/apache2/sites-available/$SERVERNAME.conf
    else
        echo "" >> /etc/apache2/sites-available/$SERVERNAME.conf
    fi
    echo "" >> /etc/apache2/sites-available/$SERVERNAME.conf
    echo "        <Directory />" >> /etc/apache2/sites-available/$SERVERNAME.conf
    echo "                Options -Indexes +FollowSymLinks +MultiViews" >> /etc/apache2/sites-available/$SERVERNAME.conf
    echo "                AllowOverride All" >> /etc/apache2/sites-available/$SERVERNAME.conf
    echo "                Require all granted" >> /etc/apache2/sites-available/$SERVERNAME.conf
    echo "        </Directory>" >> /etc/apache2/sites-available/$SERVERNAME.conf
    echo "" >> /etc/apache2/sites-available/$SERVERNAME.conf
    echo "        <FilesMatch \".+\.ph(p[3457]?|t|tml)$\">" >> /etc/apache2/sites-available/$SERVERNAME.conf
    echo "            SetHandler \"proxy:unix:/run/php/php$PHP_FPM_VERSION-fpm-$WEBSITE_NAME.sock|fcgi://localhost\"" >> /etc/apache2/sites-available/$SERVERNAME.conf
    echo "        </FilesMatch>" >> /etc/apache2/sites-available/$SERVERNAME.conf
    echo "" >> /etc/apache2/sites-available/$SERVERNAME.conf
    echo "        ErrorLog \${APACHE_LOG_DIR}/$SERVERNAME-error.log" >> /etc/apache2/sites-available/$SERVERNAME.conf
    echo "        LogLevel warn" >> /etc/apache2/sites-available/$SERVERNAME.conf
    echo "        CustomLog \${APACHE_LOG_DIR}/$SERVERNAME-access.log combined" >> /etc/apache2/sites-available/$SERVERNAME.conf
    echo "</VirtualHost>" >> /etc/apache2/sites-available/$SERVERNAME.conf
    echo -e "${GREEN}File created ${NC}\n"
}

function enable_virtualhost {
    echo -e "${YELLOW}Adding the VirtualHost to enabled sites ${NC}" 
    a2ensite $SERVERNAME.conf
    echo -e "${GREEN}Site added ${NC}\n" 
}

function restart_apache_service {
    # Check if the Apache configuration is correct
    apache2ctl -t
    # Restart the Apache service if the Apache configuration is correct
    if [ "$?" -eq "0" ]; then
        echo -e "${YELLOW}Restarting the Apache service ${NC}" 
        systemctl reload apache2
        systemctl status apache2 --no-pager
        echo -e "${GREEN}Service restarted ${NC}\n" 
    fi
}

function get_lets_encrypt_certificates {
    if command_exists $CERT_BINARY_FULL_PATH; then
        echo -e "${YELLOW}Obtaining the SSL certificates ${NC}" 
        COMMAND="$CERT_BINARY_FULL_PATH certonly --webroot -w $NEW_PATH -d $SERVERNAME " 
        for site in $SERVERALIAS; do
            COMMAND+="-d $site "
        done
        $COMMAND
        # Update the Apache virtualhost if the certbot command is correct
        if [ "$?" -eq "0" ]; then
            ADD_SSL_TO_APACHE_VIRTUALHOST="yes"
        else
            ADD_SSL_TO_APACHE_VIRTUALHOST="no"
        fi
        echo -e "${GREEN}Certificates obtained ${NC}\n" 
    fi
}

function add_ssl_to_apache_virtualhost {
    if [ $ADD_SSL_TO_APACHE_VIRTUALHOST = "yes" ]; then
        echo -e "${YELLOW}Updating the Apache virtualhost file: /etc/apache2/sites-available/$SERVERNAME.conf ${NC}" 
        sed -e '6i\ \ \ \ \ \ \ \ RewriteEngine On' -i /etc/apache2/sites-available/$SERVERNAME.conf
        sed -e '7i\ \ \ \ \ \ \ \ RewriteCond %{HTTPS} !=on' -i /etc/apache2/sites-available/$SERVERNAME.conf
        sed -e '8i\ \ \ \ \ \ \ \ RewriteRule ^/?(.*) https://%{SERVER_NAME}/$1 [R=301,L]' -i /etc/apache2/sites-available/$SERVERNAME.conf
        sed -e '9i\ ' -i /etc/apache2/sites-available/$SERVERNAME.conf
        echo "<VirtualHost *:443>" >> /etc/apache2/sites-available/$SERVERNAME.conf
        echo "        DocumentRoot $NEW_PATH" >> /etc/apache2/sites-available/$SERVERNAME.conf
        echo "        ServerName $SERVERNAME" >> /etc/apache2/sites-available/$SERVERNAME.conf
        if [ -n "$SERVERALIAS" ]; then
            echo "        ServerAlias $SERVERALIAS" >> /etc/apache2/sites-available/$SERVERNAME.conf
        else
            echo "" >> /etc/apache2/sites-available/$SERVERNAME.conf
        fi
        echo "" >> /etc/apache2/sites-available/$SERVERNAME.conf
        echo "        <Directory />" >> /etc/apache2/sites-available/$SERVERNAME.conf
        echo "                Options -Indexes +FollowSymLinks +MultiViews" >> /etc/apache2/sites-available/$SERVERNAME.conf
        echo "                AllowOverride All" >> /etc/apache2/sites-available/$SERVERNAME.conf
        echo "                Require all granted" >> /etc/apache2/sites-available/$SERVERNAME.conf
        echo "        </Directory>" >> /etc/apache2/sites-available/$SERVERNAME.conf
        echo "" >> /etc/apache2/sites-available/$SERVERNAME.conf
        echo "        <FilesMatch \".+\.ph(p[3457]?|t|tml)$\">" >> /etc/apache2/sites-available/$SERVERNAME.conf
        echo "            SetHandler \"proxy:unix:/run/php/php$PHP_FPM_VERSION-fpm-$WEBSITE_NAME.sock|fcgi://localhost\"" >> /etc/apache2/sites-available/$SERVERNAME.conf
        echo "        </FilesMatch>" >> /etc/apache2/sites-available/$SERVERNAME.conf
        echo "" >> /etc/apache2/sites-available/$SERVERNAME.conf
        echo "        SSLEngine on" >>  /etc/apache2/sites-available/$SERVERNAME.conf
        echo "        SSLCertificateFile /etc/letsencrypt/live/$SERVERNAME/certpem" >>  /etc/apache2/sites-available/$SERVERNAME.conf
        echo "        SSLCertificateKeyFile /etc/letsencrypt/live/$SERVERNAME/privkey.pem" >>  /etc/apache2/sites-available/$SERVERNAME.conf
        echo "        SSLCertificateChainFile /etc/letsencrypt/live/$SERVERNAME/chain.pem" >>  /etc/apache2/sites-available/$SERVERNAME.conf
        echo "" >> /etc/apache2/sites-available/$SERVERNAME.conf
        echo "        ErrorLog \${APACHE_LOG_DIR}/$SERVERNAME-error.log" >> /etc/apache2/sites-available/$SERVERNAME.conf
        echo "        LogLevel warn" >> /etc/apache2/sites-available/$SERVERNAME.conf
        echo "        CustomLog \${APACHE_LOG_DIR}/$SERVERNAME-access.log combined" >> /etc/apache2/sites-available/$SERVERNAME.conf
        echo "</VirtualHost>" >> /etc/apache2/sites-available/$SERVERNAME.conf
        echo -e "${GREEN}File updated ${NC}\n"
    else
        echo -e "${RED}The $CERT_BINARY_FULL_PATH has some problems geting the certificates. The Apache virtualhost file has not been updated ${NC}\n" 
    fi
}

function replace_http_with_https {
    if [ $ADD_SSL_TO_APACHE_VIRTUALHOST = "yes" ]; then    
        echo -e "${YELLOW}Replacing http with https ${NC}" 
        wp search-replace "http://$NEW_WORDPRESS_URL" "https://$NEW_WORDPRESS_URL" --path="$NEW_PATH" --all-tables --allow-root
        echo -e "${GREEN}Replace done ${NC}\n" 
    fi
}

clear 
check_if_the_user_is_sudo
check_if_wp_cli_is_installed
create_database
create_new_user
create_folder_for_website
install_wordpress
# remove installed plugins
update_propietary_and_permissions
create_php_fpm_file
restart_php_fpm_service
create_apache_virtualhost
enable_virtualhost 
restart_apache_service
get_lets_encrypt_certificates
add_ssl_to_apache_virtualhost
restart_apache_service
replace_http_with_https