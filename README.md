# Server scripts

This project contains a set of scripts useful for handling Linux servers. 

Currently there is only 2 scripts, which allows:
* move a LAMP site between servers. 
* remove a LAMP site in a server. 

LAMP site: WordPress, Laravel, Symfony, Magento,...

## Scripts

### Move LAMP between servers

This script move LAMP site (WordPress, Laravel, Symfony, Magento,...) between 
different Linux Servers.

Execute this script on the destination machine with root privileges. If you 
want to use the remote certificates, the remote user should be sudoer to be 
able to access the certificates.

The configuration is stored in a different file: 
move-lamp-between-servers-variables.sh by default, but you can pass it as the 
first parameter.

This script was tested in Debian machines. It should work on Ubuntu
and on Red Hat/CentOS/Fedora with small changes.

This script executes these steps:
* Make a remote tar.gz with the project files in the remote server.
* Copy this file from the remote server to the local server.
* Make a MySQL dump in the remote server.
* Copy this file from the remote server to the local server.
* (Optional) Make a remote tar.gz with the certificates.
* Copy this file from the remote server to the local server.
* Create a new local user.
* Create the local folder for the files, unzip the backup and change the owner.
* Create the MySQL database and the user.
* Restore the MySQL dump.
* (Optional) Create the local folder for the certificates, unzip the backup 
and change the owner.
* Create the PHP-FPM file.
* Restart the PHP-FPM service.
* Create the Apache virtualhost.
* Add the virtualhost to the enabled sites.
* Restart the Apache service if the Apache configuration is correct.

#### Execution

To execute this script:
* Create a new file with the variables:
```
$ cp move-lamp-between-servers-variables.sh.example move-lamp-between-servers-variables.sh
```
* Adjust the variables of the **move-lamp-between-servers-variables.sh** file 
to your needs.
* Execute the script as sudo user. If you have selected the option to use the 
remote certificates, the script will ask you to enter the password of the 
remote sudoer user.
```
$ sudo move-lamp-between-servers.sh
```

### Remove LAMP site

This script remove a LAMP site (WordPress, Laravel, Symfony, Magento,...) in a Linux Server.

This script executes these steps:
* Make a full backup: files, MySQL, certificates and configuration (PHP-FPM and Apache).
* Remove the PHP-FPM files and restart the service.
* Remove the Apache files and restart the service if the Apache configuration is correct.
* Remove the project files and restart the service.
* Remove the username and its files.
* Remove the MySQL database and the user.
* Revoke and delete the Let's Encrypt certificate.

To execute this script:
* Create a new file with the variables:
```
$ cp remove-lamp-site-variables.sh.example remove-lamp-site-variables.sh
```
* Adjust the variables of the **remove-lamp-site-variables.sh** file to your needs.
* Execute the script as sudo user:
```
$ sudo remove-lamp-site.sh
```

## Todo
* Use sshpass to make the remote certificates backup.
* Make optional the verbose configuration.
* Make an option to delete the remote and the local backups.
* Compress the SQL dump.

## License
[GNU Affero General Public License v3 or higher](https://www.gnu.org/licenses/agpl-3.0.en.html)