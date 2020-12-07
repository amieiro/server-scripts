#!/bin/bash

# This script install a WordPress in a LAMP environment: Debian, Apache2, 
# MySQL and PHP-FPM

NEW_MYSQL_DATABASE='my_database'
NEW_MYSQL_USERNAME="my_username"
NEW_MYSQL_PASSWORD="abcde" #`openssl rand --base64 32`
MYSQL_ADMIN_USERNAME="homestead"
MYSQL_ADMIN_PASSWORD="secret"
NEW_USERNAME="new_username"
NEW_PASSWORD=`openssl rand --base64 32`
NEW_PATH="/var/www/$NEW_USERNAME/wordpress"
PROJECT_NAME="my_project"                                                       # Project name
NEW_WORDPRESS_LOCALE="es_ES"
NEW_WORDPRESS_URL="https://www.example.com"
NEW_WORDPRESS_TITLE="My new title"
NEW_WORDPRESS_ADMIN_USERNAME="My_new_WP_user"
NEW_WORDPRESS_ADMIN_PASSWORD=`openssl rand --base64 32`
NEW_WORDPRESS_ADMIN_EMAIL="info@example.com"                                    #
PHP_FPM_VERSION="7.4"                                                           # PHP-FPM version
SERVERNAME="mywebsite.com"                                                      # Servername (Apache parameter)
SERVERALIAS="www.mywebsite.com subdomain.mywebsite.com"                         # Serveralias (Apache parameter)
PHP_FPM_MEMORY_LIMIT="256M"                                                     # PHP-FPM memory limit (PHP-FPM parameter)

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

function check_if_certbot_is_installed {   
    if ! command_exists certbot; then
        echo "You must have the Certbot installed. Please, check https://certbot.eff.org/instructions"
        return 0
    else
        return 1
    fi
}

clear 

check_if_the_user_is_sudo
check_if_wp_cli_is_installed

# Create the database 
echo -e "\n${YELLOW}Creating the MySQL database and the user to access to it ${NC}" 
mysql --user="$MYSQL_ADMIN_USERNAME" --password="$MYSQL_ADMIN_PASSWORD" -e "CREATE DATABASE $NEW_MYSQL_DATABASE CHARACTER SET utf8 COLLATE utf8_general_ci;" 
mysql --user="$MYSQL_ADMIN_USERNAME" --password="$MYSQL_ADMIN_PASSWORD" -e "CREATE USER '$NEW_MYSQL_USERNAME'@'localhost' identified by '$NEW_MYSQL_PASSWORD';" 
mysql --user="$MYSQL_ADMIN_USERNAME" --password="$MYSQL_ADMIN_PASSWORD" -e "GRANT ALL PRIVILEGES ON $NEW_MYSQL_DATABASE.* TO $NEW_MYSQL_USERNAME@localhost;" 
mysql --user="$MYSQL_ADMIN_USERNAME" --password="$MYSQL_ADMIN_PASSWORD" -e "FLUSH PRIVILEGES;" 
echo -e "${GREEN}Database and user created. Password for the $NEW_MYSQL_USERNAME user: $NEW_MYSQL_PASSWORD ${NC}\n" 

# Create the new user
echo -e "\n${YELLOW}Creating the new user ${NC}" 
adduser --disabled-login --system --group --shell=/bin/false $NEW_USERNAME
echo -e "${GREEN}User created ${NC}\n"

# Create the folder for the website
echo -e "\n${YELLOW}Creating the folder for the website: $NEW_PATH ${NC}" 
rm $NEW_PATH -rf # todo: borrar
mkdir -p $NEW_PATH
echo -e "${GREEN}Folder created ${NC}\n" 

echo -e "${YELLOW}Downloading the WordPress core ${NC}" 
wp core download --path="$NEW_PATH" --allow-root
echo -e "${GREEN}WordPress core downloaded ${NC}\n" 
echo -e "${YELLOW}Creating the wp-config.php file ${NC}" 
wp config create --dbname=$NEW_MYSQL_DATABASE --dbuser=$NEW_MYSQL_USERNAME --dbpass="$NEW_MYSQL_PASSWORD" --locale=$NEW_WORDPRESS_LOCALE --path="$NEW_PATH" --allow-root
echo -e "${GREEN}wp-config.php created ${NC}\n" 
echo -e "${YELLOW}Installing WordPress ${NC}" 
wp core install --url="$NEW_WORDPRESS_URL" --title="$NEW_WORDPRESS_TITLE" --admin_user="$NEW_WORDPRESS_USERNAME" --admin_password="$NEW_WORDPRESS_ADMIN_PASSWORD" --admin_email="$NEW_WORDPRESS_ADMIN_EMAIL"  --path="$NEW_PATH" --allow-root
echo -e "${GREEN}WordPress installed ${NC}\n" 

# Change the propietary and the permissions of the files
echo -e "${YELLOW}Changing the propietary of the files: $NEW_PATH ${NC}" 
chown $NEW_USERNAME:$NEW_USERNAME $NEW_PATH -R
find . -type d -exec chmod 755 {} \;
find . -type f -exec chmod 644 {} \;
echo -e "${GREEN}Propietary changed ${NC}\n" 

# Create the PHP-FPM file
echo -e "${YELLOW}Creating the PHP-FPM file: /etc/php/$PHP_FPM_VERSION/fpm/pool.d/$SERVERNAME.conf ${NC}" 
echo "[$NEW_USERNAME]" > /etc/php/$PHP_FPM_VERSION/fpm/pool.d/$SERVERNAME.conf
echo "user = $NEW_USERNAME" >> /etc/php/$PHP_FPM_VERSION/fpm/pool.d/$SERVERNAME.conf
echo "group = $NEW_USERNAME" >> /etc/php/$PHP_FPM_VERSION/fpm/pool.d/$SERVERNAME.conf
echo "" >> /etc/php/$PHP_FPM_VERSION/fpm/pool.d/$SERVERNAME.conf
echo "listen = /run/php/php$PHP_FPM_VERSION-fpm-$PROJECT_NAME.sock" >> /etc/php/$PHP_FPM_VERSION/fpm/pool.d/$SERVERNAME.conf
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

# Restart the PHP-FPM service
echo -e "${YELLOW}Restarting the PHP-FPM $PHP_FPM_VERSION service ${NC}" 
systemctl reload php$PHP_FPM_VERSION-fpm
systemctl status php$PHP_FPM_VERSION-fpm --no-pager
echo -e "${GREEN}Service restarted ${NC}\n" 

# Create the Apache virtualhost
echo -e "${YELLOW}Creating the Apache virtualhost PHP-FPM file: /etc/apache2/sites-available/$SERVERNAME.conf ${NC}" 

echo "<VirtualHost *:80>" > /etc/apache2/sites-available/$SERVERNAME.conf
echo "        DocumentRoot $NEW_PATH" >> /etc/apache2/sites-available/$SERVERNAME.conf
echo "        ServerName $SERVERNAME" >> /etc/apache2/sites-available/$SERVERNAME.conf
if [ -n "$SERVERALIAS" ]; then
    echo "        ServerAlias $SERVERALIAS" >> /etc/apache2/sites-available/$SERVERNAME.conf
fi
echo "" >> /etc/apache2/sites-available/$SERVERNAME.conf
echo "        <Directory />" >> /etc/apache2/sites-available/$SERVERNAME.conf
echo "                Options -Indexes +FollowSymLinks +MultiViews" >> /etc/apache2/sites-available/$SERVERNAME.conf
echo "                AllowOverride All" >> /etc/apache2/sites-available/$SERVERNAME.conf
echo "                Require all granted" >> /etc/apache2/sites-available/$SERVERNAME.conf
echo "        </Directory>" >> /etc/apache2/sites-available/$SERVERNAME.conf
echo "" >> /etc/apache2/sites-available/$SERVERNAME.conf
echo "        <FilesMatch \".+\.ph(p[3457]?|t|tml)$\">" >> /etc/apache2/sites-available/$SERVERNAME.conf
echo "            SetHandler \"proxy:unix:/run/php/php$PHP_FPM_VERSION-fpm-$PROJECT_NAME.sock|fcgi://localhost\"" >> /etc/apache2/sites-available/$SERVERNAME.conf
echo "        </FilesMatch>" >> /etc/apache2/sites-available/$SERVERNAME.conf
echo "" >> /etc/apache2/sites-available/$SERVERNAME.conf
echo "        ErrorLog \${APACHE_LOG_DIR}/$SERVERNAME-error.log" >> /etc/apache2/sites-available/$SERVERNAME.conf
echo "        LogLevel warn" >> /etc/apache2/sites-available/$SERVERNAME.conf
echo "        CustomLog \${APACHE_LOG_DIR}/$SERVERNAME-access.log combined" >> /etc/apache2/sites-available/$SERVERNAME.conf
echo "</VirtualHost>" >> /etc/apache2/sites-available/$SERVERNAME.conf
echo -e "${GREEN}File created ${NC}\n" 

# Add the virtualhost to the enabled sites
echo -e "${YELLOW}Adding the VirtualHost to enabled sites ${NC}" 
a2ensite $SERVERNAME.conf
echo -e "${GREEN}Site added ${NC}\n" 

# Check if the Apache configuration is correct
apache2ctl -t

# Restart the Apache service if the Apache configuration is correct
if [ "$?" -eq "0" ]; then
    echo -e "${YELLOW}Restarting the Apache service ${NC}" 
    systemctl reload apache2
    systemctl status apache2 --no-pager
    echo -e "${GREEN}Service restarted ${NC}\n" 
fi

# Obtain the Let's Encrypt certificates
if command_exists certbot; then
    COMMAND="certbot certonly --webroot -w $NEW_PATH -d $SERVERNAME " 
    for site in $SERVERALIAS; do
        COMMAND+="-d $site "
    done
    $COMMAND
    # Update the Apache virtualhost if the certbot command is correct
    if [ "$?" -eq "0" ]; then
        echo "Comando correcto"
    fi
exit
fi