#!/bin/bash

# This script remove a LAMP project (WordPress, Laravel, Symfony, Magento,...) 
# in a LAMP environment: Debian, Apache2, MySQL and PHP-FPM

function command_exists () {
    command -v $1 >/dev/null 2>&1;
}

function check_if_the_user_is_sudo {
    if [ ${EUID:-$(id -u)} -ne 0 ]; then
        echo -e "${RED}This script must be executed as root ${NC}"
        exit
    fi 
}

function ask_for_confirmation {
    read -p "Are you sure you want to delete $PROJECT_DOMAIN and all its related items (y/n)? " answer
    case ${answer:0:1} in
        y|Y )
            echo -e "\n${YELLOW}Starting the work ${NC}"  
        ;;
        * )
            exit
        ;;
    esac
}

function load_environment_variables {
    # Load the variables from an external file
    ENVIRONMENT_VARIABLES_FILE="remove-lamp-site-variables.sh"
    if [ -n "$1" ]; then
        ENVIRONMENT_VARIABLES_FILE=$1
    fi
    CURRENT_DIR="$(dirname "$0")"
    # Load the external variables
    . "$CURRENT_DIR/$ENVIRONMENT_VARIABLES_FILE"
}

function make_full_backup {
    if [ $MAKE_LOCAL_BACKUP = "yes" ]; then
        if [ $REMOVE_MYSQL_DATABASE = "yes" ]; then
            echo -e "\n${YELLOW}Creating the MySQL database backup ${NC}" 
            mysqldump --user="$MYSQL_ADMIN_USERNAME" --password="$MYSQL_ADMIN_PASSWORD" $MYSQL_DATABASE > $PATH_TO_STORE_THE_BACKUP$TIMESTAMP-$PROJECT_DOMAIN.sql
            echo -e "${GREEN}Backup created ${NC}\n"
        fi
        if [ $REMOVE_PROJECT_FILES = "yes" ]; then
            echo -e "\n${YELLOW}Creating a backup for the files ${NC}" 
            tar czf $PATH_TO_STORE_THE_BACKUP$TIMESTAMP-$PROJECT_DOMAIN.tar.gz -C $PROJECT_FULL_PATH .
            echo -e "${GREEN}Backup created ${NC}\n" 
        fi
        if [ $REMOVE_CERTIFICATES = "yes" ]; then
            echo -e "\n${YELLOW}Creating a backup for the certificates ${NC}" 
            sudo tar czf $PATH_TO_STORE_THE_BACKUP$TIMESTAMP-$PROJECT_DOMAIN-certificates.tar.gz -C $CERTIFICATES_ROOT_PATH .
            echo -e "${GREEN}Backup created ${NC}\n"
        fi 
        if [ $REMOVE_FPM_SITE = "yes" ]; then
            echo -e "\n${YELLOW}Creating a backup for the PHP-FPM files ${NC}" 
            sudo tar czf $PATH_TO_STORE_THE_BACKUP$TIMESTAMP-$PROJECT_DOMAIN-php-fpm.tar.gz -C $PHP_FPM_ROOT_PATH .
            echo -e "${GREEN}Backup created ${NC}\n"
        fi 
        if [ $REMOVE_APACHE_SITE = "yes" ]; then
            echo -e "\n${YELLOW}Creating a backup for the Apache files ${NC}" 
            sudo tar czf $PATH_TO_STORE_THE_BACKUP$TIMESTAMP-$PROJECT_DOMAIN-apache.tar.gz -C $APACHE_ROOT_PATH .
            echo -e "${GREEN}Backup created ${NC}\n"
        fi 
        echo -e "${GREEN}All the backups created${NC}" 
        ls -la $PATH_TO_STORE_THE_BACKUP/$TIMESTAMP*
        echo -e "\n"
    fi
}

function remove_fpm_site {
    if [ $REMOVE_FPM_SITE = "yes" ]; then
        echo -e "${YELLOW}Deleting the PHP-FPM $LOCAL_PHP_FPM_VERSION config file: $FPM_CONFIG_FULL_PATH ${NC}" 
        rm $FPM_CONFIG_FULL_PATH
        echo -e "${GREEN}File deleted ${NC}\n"
        echo -e "${YELLOW}Restarting the PHP-FPM $LOCAL_PHP_FPM_VERSION service ${NC}" 
        systemctl reload php$LOCAL_PHP_FPM_VERSION-fpm
        systemctl status php$LOCAL_PHP_FPM_VERSION-fpm --no-pager
        echo -e "${GREEN}Service restarted ${NC}\n" 
    fi
}

function remove_apache_site {
    if [ $REMOVE_APACHE_SITE = "yes" ]; then
        echo -e "${YELLOW}Disabling the Apache2 site ${NC}" 
        a2dissite $APACHE_CONFIG_FILE
        echo -e "${GREEN}Site disabled ${NC}\n"

        # Check if the Apache configuration is correct
        apache2ctl -t
        # Restart the Apache service if the Apache configuration is correct
        if [ "$?" -eq "0" ]; then
            echo -e "${YELLOW}Restarting the Apache service ${NC}" 
            systemctl reload apache2
            systemctl status apache2 --no-pager
            echo -e "${GREEN}Service restarted ${NC}\n" 
        fi

        echo -e "${YELLOW}Deleting the Apache config file: $APACHE_CONFIG_FULL_PATH ${NC}" 
        rm $APACHE_CONFIG_FULL_PATH
        echo -e "${GREEN}File deleted ${NC}\n"
    fi
}

function remove_project_files {
    if [ $REMOVE_PROJECT_FILES = "yes" ]; then
        echo -e "${YELLOW}Deleting the files: $PROJECT_FULL_PATH ${NC}" 
        rm $PROJECT_FULL_PATH -rf
        echo -e "${GREEN}Files deleted ${NC}\n"
    fi 
}

function remove_username {
    if [ $REMOVE_USERNAME = "yes" ]; then
        echo -e "${YELLOW}Deleting the local user: $USERNAME ${NC}"
        deluser $USERNAME
        echo -e "${GREEN}Local user deleted ${NC}\n"
    fi
    if [ $REMOVE_USERNAME_FILES = "yes" ]; then
        echo -e "${YELLOW}Deleting the files of the local user: /home/$USERNAME ${NC}"
        rm /home/$USERNAME -rf
        echo -e "${GREEN}Files deleted ${NC}\n"
    fi
}

function remove_mysql {
    if [ $REMOVE_MYSQL_DATABASE = "yes" ]; then
        echo -e "${YELLOW}Deleting the MySQL database: $MYSQL_DATABASE ${NC}"
        mysql --user="$MYSQL_ADMIN_USERNAME" --password="$MYSQL_ADMIN_PASSWORD" -e "DROP DATABASE $MYSQL_DATABASE;" 
        echo -e "${GREEN}Database deleted ${NC}\n"
    fi
    if [ $REMOVE_MYSQL_USERNAME = "yes" ]; then
        echo -e "${YELLOW}Deleting the MySQL user: $MYSQL_USERNAME ${NC}"
        mysql --user="$MYSQL_ADMIN_USERNAME" --password="$MYSQL_ADMIN_PASSWORD" -e "DROP USER '$MYSQL_USERNAME'@'localhost';" 
        echo -e "${GREEN}User deleted ${NC}\n"
    fi
}

function remove_certificates {
    if [ $REMOVE_CERTIFICATES = "yes" ]; then
        echo -e "${YELLOW}Revoking and deleting the certificates: $CERT_PEM_FULL_PATH ${NC}" 
        certbot revoke --cert-path $CERT_PEM_FULL_PATH --delete-after-revoke
        echo -e "${GREEN}Certificates revoked and deleted ${NC}\n"
    fi    
}



clear 
load_environment_variables
check_if_the_user_is_sudo
ask_for_confirmation
make_full_backup
remove_fpm_site
remove_apache_site
remove_project_files
remove_username
remove_mysql
remove_certificates