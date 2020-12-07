#!/bin/bash

# This script move LAMP projects (WordPress/Magento/Laravel,...) between
# different Linux Servers

function press_any_key {
  read -n 1 -s -r -p "Press any key to continue"
  echo ""
}

function check_if_the_user_is_sudo {
    if [ ${EUID:-$(id -u)} -ne 0 ]; then
        echo -e "${RED}This script must be executed as root ${NC}"
        exit
    fi 
}

# Load the variables from an external file
ENVIROMENT_VARIABLES_FILE="move-lamp-between-servers-variables.sh"
if [ -n "$1" ]; then
    ENVIROMENT_VARIABLES_FILE=$1
fi
CURRENT_DIR="$(dirname "$0")"
# Load the external variables
. "$CURRENT_DIR/$ENVIROMENT_VARIABLES_FILE"

clear 
check_if_the_user_is_sudo

# Make the backup in the remote server
echo -e "${YELLOW}Creating the backup of the files in the remote server${NC}" 
ssh $REMOTE_SSH_USERNAME@$REMOTE_SERVER -p $REMOTE_SSH_PORT "tar czf $REMOTE_PATH_TO_MAKE_THE_BACKUP$TIMESTAMP-$REMOTE_PROJECT_NAME.tar.gz -C $REMOTE_PATH_TO_BACKUP ."
echo -e "${GREEN}Backup created${NC}\n" 

# Delete older file backups
echo -e "${YELLOW}Deleting older local file backups ${NC}" 
rm $LOCAL_PATH_TO_STORE_THE_BACKUP$TIMESTAMP-$REMOTE_PROJECT_NAME.tar.gz -rf
echo -e "${GREEN}Backups deleted ${NC}\n" 

# Get the remote files' backup
echo -e "${YELLOW}Donwloading the backup from the remote server${NC}" 
scp -P $REMOTE_SSH_PORT $REMOTE_SSH_USERNAME@$REMOTE_SERVER:$REMOTE_PATH_TO_MAKE_THE_BACKUP$TIMESTAMP-$REMOTE_PROJECT_NAME.tar.gz $LOCAL_PATH_TO_STORE_THE_BACKUP
echo -e "${GREEN}Backup donwloaded${NC}\n" 

# Make the MySQL dump
echo -e "${YELLOW}Creating the MySQL backup in the remote server${NC}" 
ssh $REMOTE_SSH_USERNAME@$REMOTE_SERVER -p $REMOTE_SSH_PORT "mysqldump --user="$REMOTE_MYSQL_USERNAME" --password="$REMOTE_MYSQL_PASSWORD" --host="$REMOTE_MYSQL_HOST" $REMOTE_MYSQL_DATABASE > $REMOTE_PATH_TO_MAKE_THE_BACKUP$TIMESTAMP-$REMOTE_PROJECT_NAME.sql"
echo -e "${GREEN}MySQL backup created${NC}\n" 

# Delete older MySQL backups
echo -e "${YELLOW}Deleting older local MySQL backups ${NC}" 
rm $LOCAL_PATH_TO_STORE_THE_BACKUP$TIMESTAMP-$REMOTE_PROJECT_NAME.sql -rf
echo -e "${GREEN}MySQL backup deleted ${NC}\n" 

# Get the remote MySQL backup
echo -e "${YELLOW}Donwloading the MySQL backup from the remote server${NC}" 
scp -P $REMOTE_SSH_PORT $REMOTE_SSH_USERNAME@$REMOTE_SERVER:$REMOTE_PATH_TO_MAKE_THE_BACKUP$TIMESTAMP-$REMOTE_PROJECT_NAME.sql $LOCAL_PATH_TO_STORE_THE_BACKUP
echo -e "${GREEN}MySQL backup donwloaded${NC}\n" 

# Check if you want to download the Let's Encrypt certificates
if [ $USE_REMOTE_LETSENCRYPT_CERTIFICATES = "yes" ]; then
    # Make the certificates backup in the remote server
    echo -e "${YELLOW}Creating the backup certificates in the remote server${NC}" 
    echo -e "${YELLOW}Insert the password of $REMOTE_SSH_USERNAME@$REMOTE_SERVER ${NC}" 
    ssh -t $REMOTE_SSH_USERNAME@$REMOTE_SERVER -p $REMOTE_SSH_PORT "sudo tar czhf $REMOTE_PATH_TO_MAKE_THE_BACKUP$TIMESTAMP-$REMOTE_PROJECT_NAME-certificates.tar.gz -C $REMOTE_LETSENCRYPT_PATH ."
    echo -e "${GREEN}Backup created${NC}\n" 

    # Delete older file backups
    echo -e "${YELLOW}Deleting older certificate backups ${NC}" 
    rm $LOCAL_PATH_TO_STORE_THE_BACKUP$TIMESTAMP-$REMOTE_PROJECT_NAME-certificates.tar.gz -rf
    echo -e "${GREEN}Backups deleted ${NC}\n" 

    # Get the remote files' backup
    echo -e "${YELLOW}Donwloading the backup certificates from the remote server${NC}" 
    scp -P $REMOTE_SSH_PORT $REMOTE_SSH_USERNAME@$REMOTE_SERVER:$REMOTE_PATH_TO_MAKE_THE_BACKUP$TIMESTAMP-$REMOTE_PROJECT_NAME-certificates.tar.gz $LOCAL_PATH_TO_STORE_THE_BACKUP
    echo -e "${GREEN}Backup donwloaded${NC}\n" 
fi

# Show the downloaded files
echo -e "${GREEN}Downloaded files${NC}" 
ls -la $LOCAL_PATH_TO_STORE_THE_BACKUP/$TIMESTAMP*

# Create the local user
echo -e "\n${YELLOW}Creating the local user ${NC}" 
adduser --disabled-login --system --group --shell=/bin/false $LOCAL_NEW_USERNAME
echo -e "${GREEN}User created ${NC}\n" 

# Create the folder for the website
echo -e "\n${YELLOW}Creating the folder for the website: $LOCAL_PATH ${NC}" 
mkdir -p $LOCAL_PATH
echo -e "${GREEN}Folder created ${NC}\n" 

# Unzip the file backup
echo -e "${YELLOW}Unzipping the backup of the files to: $LOCAL_PATH ${NC}" 
tar xzf  $LOCAL_PATH_TO_STORE_THE_BACKUP$TIMESTAMP-$REMOTE_PROJECT_NAME.tar.gz --directory $LOCAL_PATH
echo -e "${GREEN}Backup unzipped ${NC}\n" 

# Change the propietary of the files
echo -e "${YELLOW}Changing the propietary of the files: $LOCAL_PATH ${NC}" 
chown $LOCAL_NEW_USERNAME:$LOCAL_NEW_USERNAME $LOCAL_PATH -R 
echo -e "${GREEN}Propietary changed ${NC}\n" 

# Create the database 
echo -e "\n${YELLOW}Creating the MySQL database and the user to access to it ${NC}" 
mysql --user="$LOCAL_MYSQL_ADMIN_USERNAME" --password="$LOCAL_MYSQL_ADMIN_PASSWORD" -e "CREATE DATABASE $LOCAL_MYSQL_DATABASE CHARACTER SET utf8 COLLATE utf8_general_ci;" 
mysql --user="$LOCAL_MYSQL_ADMIN_USERNAME" --password="$LOCAL_MYSQL_ADMIN_PASSWORD" -e "CREATE USER '$LOCAL_MYSQL_USERNAME'@'localhost' identified by '$LOCAL_MYSQL_PASSWORD';" 
mysql --user="$LOCAL_MYSQL_ADMIN_USERNAME" --password="$LOCAL_MYSQL_ADMIN_PASSWORD" -e "GRANT ALL PRIVILEGES ON $LOCAL_MYSQL_DATABASE.* TO $LOCAL_MYSQL_USERNAME@localhost;" 
mysql --user="$LOCAL_MYSQL_ADMIN_USERNAME" --password="$LOCAL_MYSQL_ADMIN_PASSWORD" -e "FLUSH PRIVILEGES;" 
echo -e "${GREEN}Database and user created ${NC}\n" 

# Restore the MySQL dump
echo -e "${YELLOW}Restoring the MySQL database ${NC}" 
mysql --user="$LOCAL_MYSQL_USERNAME" --password="$LOCAL_MYSQL_PASSWORD" --host="localhost" $LOCAL_MYSQL_DATABASE < $LOCAL_PATH_TO_STORE_THE_BACKUP$TIMESTAMP-$REMOTE_PROJECT_NAME.sql
echo -e "${GREEN}Database restored ${NC}\n" 

# Check if you want to use the remote Let's Encrypt certificates
if [ $USE_REMOTE_LETSENCRYPT_CERTIFICATES = "yes" ]; then
    # Create the folder for the website
    echo -e "\n${YELLOW}Creating the folder for the certificates: $LOCAL_PATH_TO_STORE_CERTIFICATES ${NC}" 
    mkdir -p $LOCAL_PATH_TO_STORE_CERTIFICATES
    echo -e "${GREEN}Folder created ${NC}\n" 

    # Unzip the file backup
    echo -e "${YELLOW}Unzipping the certificate backup to: $LOCAL_PATH_TO_STORE_CERTIFICATES ${NC}" 
    tar xzf  $LOCAL_PATH_TO_STORE_THE_BACKUP$TIMESTAMP-$REMOTE_PROJECT_NAME-certificates.tar.gz --directory $LOCAL_PATH_TO_STORE_CERTIFICATES
    echo -e "${GREEN}Backup unzipped ${NC}\n" 

    # Change the propietary of the files
    echo -e "${YELLOW}Changing the propietary of the files: $LOCAL_PATH_TO_STORE_CERTIFICATES ${NC}" 
    chown $LOCAL_NEW_USERNAME:$LOCAL_NEW_USERNAME $LOCAL_PATH_TO_STORE_CERTIFICATES -R 
    echo -e "${GREEN}Propietary changed ${NC}\n" 
fi

# Create the PHP-FPM file
echo -e "${YELLOW}Creating the PHP-FPM file: /etc/php/$LOCAL_PHP_FPM_VERSION/fpm/pool.d/$LOCAL_SERVERNAME.conf ${NC}" 
echo "[$LOCAL_NEW_USERNAME]" > /etc/php/$LOCAL_PHP_FPM_VERSION/fpm/pool.d/$LOCAL_SERVERNAME.conf
echo "user = $LOCAL_NEW_USERNAME" >> /etc/php/$LOCAL_PHP_FPM_VERSION/fpm/pool.d/$LOCAL_SERVERNAME.conf
echo "group = $LOCAL_NEW_USERNAME" >> /etc/php/$LOCAL_PHP_FPM_VERSION/fpm/pool.d/$LOCAL_SERVERNAME.conf
echo "" >> /etc/php/$LOCAL_PHP_FPM_VERSION/fpm/pool.d/$LOCAL_SERVERNAME.conf
echo "listen = /run/php/php$LOCAL_PHP_FPM_VERSION-fpm-$LOCAL_PROJECT_NAME.sock" >> /etc/php/$LOCAL_PHP_FPM_VERSION/fpm/pool.d/$LOCAL_SERVERNAME.conf
echo "listen.owner = www-data" >> /etc/php/$LOCAL_PHP_FPM_VERSION/fpm/pool.d/$LOCAL_SERVERNAME.conf
echo "listen.group = www-data" >> /etc/php/$LOCAL_PHP_FPM_VERSION/fpm/pool.d/$LOCAL_SERVERNAME.conf 
echo "pm = dynamic" >> /etc/php/$LOCAL_PHP_FPM_VERSION/fpm/pool.d/$LOCAL_SERVERNAME.conf
echo "" >> /etc/php/$LOCAL_PHP_FPM_VERSION/fpm/pool.d/$LOCAL_SERVERNAME.conf
echo "pm.max_children = 5" >> /etc/php/$LOCAL_PHP_FPM_VERSION/fpm/pool.d/$LOCAL_SERVERNAME.conf
echo "pm.start_servers = 2" >> /etc/php/$LOCAL_PHP_FPM_VERSION/fpm/pool.d/$LOCAL_SERVERNAME.conf
echo "pm.min_spare_servers = 1" >> /etc/php/$LOCAL_PHP_FPM_VERSION/fpm/pool.d/$LOCAL_SERVERNAME.conf
echo "pm.max_spare_servers = 3" >> /etc/php/$LOCAL_PHP_FPM_VERSION/fpm/pool.d/$LOCAL_SERVERNAME.conf
echo "php_admin_flag[log_errors] = on" >> /etc/php/$LOCAL_PHP_FPM_VERSION/fpm/pool.d/$LOCAL_SERVERNAME.conf
echo "catch_workers_output = yes" >> /etc/php/$LOCAL_PHP_FPM_VERSION/fpm/pool.d/$LOCAL_SERVERNAME.conf
echo "php_admin_value[memory_limit] = $LOCAL_PHP_FPM_MEMORY_LIMIT" >> /etc/php/$LOCAL_PHP_FPM_VERSION/fpm/pool.d/$LOCAL_SERVERNAME.conf
echo "" >> /etc/php/$LOCAL_PHP_FPM_VERSION/fpm/pool.d/$LOCAL_SERVERNAME.conf
# echo "php_admin_value[max_execution_time] = 20" >> /etc/php/$LOCAL_PHP_FPM_VERSION/fpm/pool.d/$LOCAL_SERVERNAME.conf
# echo "php_admin_value[post_max_size] = 18M" >> /etc/php/$LOCAL_PHP_FPM_VERSION/fpm/pool.d/$LOCAL_SERVERNAME.conf
# echo "php_admin_value[upload_max_filesize] = 16M" >> /etc/php/$LOCAL_PHP_FPM_VERSION/fpm/pool.d/$LOCAL_SERVERNAME.conf
echo -e "${GREEN}File created ${NC}\n" 

# Restart the PHP-FPM service
echo -e "${YELLOW}Restarting the PHP-FPM $LOCAL_PHP_FPM_VERSION service ${NC}" 
systemctl reload php$LOCAL_PHP_FPM_VERSION-fpm
systemctl status php$LOCAL_PHP_FPM_VERSION-fpm --no-pager
echo -e "${GREEN}Service restarted ${NC}\n" 

# Create the Apache virtualhost
echo -e "${YELLOW}Creating the Apache virtualhost PHP-FPM file: /etc/apache2/sites-available/$LOCAL_SERVERNAME.conf ${NC}" 

echo "<VirtualHost *:80>" > /etc/apache2/sites-available/$LOCAL_SERVERNAME.conf
echo "        DocumentRoot $LOCAL_PATH" >> /etc/apache2/sites-available/$LOCAL_SERVERNAME.conf
echo "        ServerName $LOCAL_SERVERNAME" >> /etc/apache2/sites-available/$LOCAL_SERVERNAME.conf
if [ -n "$LOCAL_SERVERALIAS" ]; then
    echo "        ServerAlias $LOCAL_SERVERALIAS" >> /etc/apache2/sites-available/$LOCAL_SERVERNAME.conf
fi
echo "" >> /etc/apache2/sites-available/$LOCAL_SERVERNAME.conf
echo "        <Directory />" >> /etc/apache2/sites-available/$LOCAL_SERVERNAME.conf
echo "                Options -Indexes +FollowSymLinks +MultiViews" >> /etc/apache2/sites-available/$LOCAL_SERVERNAME.conf
echo "                AllowOverride All" >> /etc/apache2/sites-available/$LOCAL_SERVERNAME.conf
echo "                Require all granted" >> /etc/apache2/sites-available/$LOCAL_SERVERNAME.conf
echo "        </Directory>" >> /etc/apache2/sites-available/$LOCAL_SERVERNAME.conf
if [ $USE_REMOTE_LETSENCRYPT_CERTIFICATES = "yes" ]; then
    echo "" >> /etc/apache2/sites-available/$LOCAL_SERVERNAME.conf
    echo "        RewriteEngine On" >> /etc/apache2/sites-available/$LOCAL_SERVERNAME.conf
    echo "        RewriteCond %{HTTPS} !=on" >> /etc/apache2/sites-available/$LOCAL_SERVERNAME.conf
    echo "        RewriteRule ^/?(.*) https://%{SERVER_NAME}/\$1 [R=301,L]" >> /etc/apache2/sites-available/$LOCAL_SERVERNAME.conf
fi
echo "" >> /etc/apache2/sites-available/$LOCAL_SERVERNAME.conf
echo "        <FilesMatch \".+\.ph(p[3457]?|t|tml)$\">" >> /etc/apache2/sites-available/$LOCAL_SERVERNAME.conf
echo "            SetHandler \"proxy:unix:/run/php/php$LOCAL_PHP_FPM_VERSION-fpm-$LOCAL_PROJECT_NAME.sock|fcgi://localhost\"" >> /etc/apache2/sites-available/$LOCAL_SERVERNAME.conf
echo "        </FilesMatch>" >> /etc/apache2/sites-available/$LOCAL_SERVERNAME.conf
echo "" >> /etc/apache2/sites-available/$LOCAL_SERVERNAME.conf
echo "        ErrorLog \${APACHE_LOG_DIR}/$LOCAL_SERVERNAME-error.log" >> /etc/apache2/sites-available/$LOCAL_SERVERNAME.conf
echo "        LogLevel warn" >> /etc/apache2/sites-available/$LOCAL_SERVERNAME.conf
echo "        CustomLog \${APACHE_LOG_DIR}/$LOCAL_SERVERNAME-access.log combined" >> /etc/apache2/sites-available/$LOCAL_SERVERNAME.conf
echo "</VirtualHost>" >> /etc/apache2/sites-available/$LOCAL_SERVERNAME.conf

if [ $USE_REMOTE_LETSENCRYPT_CERTIFICATES = "yes" ]; then
    echo "" >> /etc/apache2/sites-available/$LOCAL_SERVERNAME.conf
    echo "<VirtualHost *:443>" >> /etc/apache2/sites-available/$LOCAL_SERVERNAME.conf
    echo "        DocumentRoot $LOCAL_PATH" >> /etc/apache2/sites-available/$LOCAL_SERVERNAME.conf
    echo "        ServerName $LOCAL_SERVERNAME" >> /etc/apache2/sites-available/$LOCAL_SERVERNAME.conf
    if [ -n "$LOCAL_SERVERALIAS" ]; then
        echo "        ServerAlias $LOCAL_SERVERALIAS" >> /etc/apache2/sites-available/$LOCAL_SERVERNAME.conf
    fi
    echo "" >> /etc/apache2/sites-available/$LOCAL_SERVERNAME.conf
    echo "        <Directory />" >> /etc/apache2/sites-available/$LOCAL_SERVERNAME.conf
    echo "                Options -Indexes +FollowSymLinks +MultiViews" >> /etc/apache2/sites-available/$LOCAL_SERVERNAME.conf
    echo "                AllowOverride All" >> /etc/apache2/sites-available/$LOCAL_SERVERNAME.conf
    echo "                Require all granted" >> /etc/apache2/sites-available/$LOCAL_SERVERNAME.conf
    echo "        </Directory>" >> /etc/apache2/sites-available/$LOCAL_SERVERNAME.conf
    echo "" >> /etc/apache2/sites-available/$LOCAL_SERVERNAME.conf
    echo "        <FilesMatch \".+\.ph(p[3457]?|t|tml)$\">" >> /etc/apache2/sites-available/$LOCAL_SERVERNAME.conf
    echo "            SetHandler \"proxy:unix:/run/php/php$LOCAL_PHP_FPM_VERSION-fpm-$LOCAL_PROJECT_NAME.sock|fcgi://localhost\"" >> /etc/apache2/sites-available/$LOCAL_SERVERNAME.conf
    echo "        </FilesMatch>" >> /etc/apache2/sites-available/$LOCAL_SERVERNAME.conf
    echo "" >> /etc/apache2/sites-available/$LOCAL_SERVERNAME.conf
    echo "        SSLEngine on" >> /etc/apache2/sites-available/$LOCAL_SERVERNAME.conf
    echo "        SSLCertificateFile $LOCAL_PATH_TO_STORE_CERTIFICATES/cert.pem" >> /etc/apache2/sites-available/$LOCAL_SERVERNAME.conf
    echo "        SSLCertificateKeyFile $LOCAL_PATH_TO_STORE_CERTIFICATES/privkey.pem" >> /etc/apache2/sites-available/$LOCAL_SERVERNAME.conf
    echo "        SSLCertificateChainFile $LOCAL_PATH_TO_STORE_CERTIFICATES/chain.pem" >> /etc/apache2/sites-available/$LOCAL_SERVERNAME.conf
    echo "" >> /etc/apache2/sites-available/$LOCAL_SERVERNAME.conf
    echo "        ErrorLog \${APACHE_LOG_DIR}/$LOCAL_SERVERNAME-error.log" >> /etc/apache2/sites-available/$LOCAL_SERVERNAME.conf
    echo "        LogLevel warn" >> /etc/apache2/sites-available/$LOCAL_SERVERNAME.conf
    echo "        CustomLog \${APACHE_LOG_DIR}/$LOCAL_SERVERNAME-access.log combined" >> /etc/apache2/sites-available/$LOCAL_SERVERNAME.conf
    echo "</VirtualHost>" >> /etc/apache2/sites-available/$LOCAL_SERVERNAME.conf
fi
echo -e "${GREEN}File created ${NC}\n" 

# Add the virtualhost to the enabled sites
echo -e "${YELLOW}Adding the VirtualHost to enabled sites ${NC}" 
a2ensite $LOCAL_SERVERNAME.conf
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

echo -e "${RED}\n\n************************************************************************************* ${NC}"
echo -e "${RED} Remember to change the DNS and renew the Let\'s Encrypt certificates in this server ${NC}"
echo -e "${RED}************************************************************************************* ${NC}"
