# Server scripts

This project contains a set of scripts useful for handling Linux servers. 

Currently, the scripts available are:
* move a LAMP site between servers.
* remove a LAMP site in a server.
* install a WordPress site in a LAMP environment.
* backup WordPress sites, non-WordPress sites, and MySQL databases.
* update WordPress installations.
* check Git status.
* check server updates.
* check app vulnerabilities.
* check resource usage (disk space monitoring with alerts).

Before using any of the "check" scripts (`check-git-status.sh`, `check-server-updates.sh`, `check-app-vulnerabilities.sh`, `check-resource-usage.sh`) you must create the configuration file from the example and edit it to match your environment:

```
cp config.sh.example config.sh
# Edit config.sh and set your actual values (Webhook URL, server name, users to ping, etc.)
```

The `config.sh` file is ignored by git (see `.gitignore`) and should not be committed because it may contain sensitive information.

## Auto-update Feature

All scripts in this repository support automatic updates from the git repository. By default, each script will execute `git pull` at startup to ensure it's running the latest version. This behavior can be controlled with the `AUTO_UPDATE_SCRIPTS` variable in `config.sh`:

- `AUTO_UPDATE_SCRIPTS="true"` (default): Scripts will automatically update before execution
- `AUTO_UPDATE_SCRIPTS="false"`: Scripts will not auto-update

The auto-update process:
- Runs silently at the beginning of each script execution
- Never interrupts script execution (errors are ignored)
- The updated code will be used in the next execution (current execution continues with the loaded version)
- Works for all scripts: check-*, install-wordpress-site.sh, wp-*.sh, move-lamp-between-servers.sh, and remove-lamp-site.sh

LAMP site: WordPress, Laravel, Symfony, Magento,...

## Scripts

### Move LAMP between servers

This script moves a LAMP site (WordPress, Laravel, Symfony, Magento,...) between 
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

This script removes a LAMP site (WordPress, Laravel, Symfony, Magento,...) in a Linux Server.

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
* Execute the script as sudo user.
```
$ sudo remove-lamp-site.sh
```

### Install WordPress site

This script installs a WordPress site in a LAMP environment (Debian, Apache2, MySQL, and PHP-FPM).

This script executes these steps:
* Check if the user is sudo.
* Check if WP-CLI is installed.
* Create a new MySQL database and user.
* Create a new local user.
* Create the folder for the website.
* Install WordPress.
* Update proprietary and permissions.
* Create the PHP-FPM file and restart the service.
* Create the Apache virtualhost and enable it.
* Restart the Apache service.
* Obtain Let's Encrypt certificates and add SSL to the virtualhost.
* Replace HTTP with HTTPS.

To execute this script:
* Adjust the variables in the script to your needs.
* Execute the script as sudo user.
```
$ sudo install-wordpress-site.sh
```

### Backup WordPress sites

This script performs a backup of WordPress sites, non-WordPress sites, and MySQL databases.

This script executes these steps:
* Create a backup directory organized by date.
* Find all WordPress installations and back up their directories.
* Back up non-WordPress sites.
* Back up all MySQL databases.

To execute this script:
* Adjust the variables in the script to your needs.
* Execute the script as sudo user.
```
$ sudo wp-backup.sh
```

### Update WordPress installations

This script updates WordPress installations.

This script executes these steps:
* Find all WordPress installations.
* Optionally back up files and databases.
* Update WordPress core.
* Remove inactive plugins and themes.
* Clean up old backups.

To execute this script:
* Adjust the variables in the script to your needs.
* Execute the script as sudo user.
```
$ sudo wp-update.sh
```

### Check Git status

This script recursively searches for Git repositories and checks for modified or untracked files. It can output results to the console or send a formatted report to a Slack channel via Webhook.

This script executes these steps:
* Recursively find Git repositories starting from a specified directory (default: /home).
* Optionally include or exclude repositories inside "vendor" or "node_modules" folders.
* For each repository, check for modified and untracked files using git status.
* Generate a summary report with counts of modified and untracked files per repository.
* Send the report to a Slack channel via webhook or print it to the console.

To execute this script:
* Adjust the variables in the script to your needs (e.g., Slack webhook URL, server name, users to ping).
* Execute the script with optional parameters for directory and flags.
```
$ ./check-git-status.sh [DIRECTORY] [include-vendor] [include-node-modules] [no-webhook]
```

### Check server updates

This script checks for pending OS updates and packages that can be removed on Debian/Ubuntu based systems. It reports findings to Slack via Webhook or prints to the console.

This script executes these steps:
* Update the package lists.
* Count the number of upgradable packages.
* Count the number of packages that can be autoremoved.
* Check if a system reboot is required.
* Generate a report with the counts and reboot status.
* Send the report to a Slack channel via webhook or print it to the console.

To execute this script:
* Adjust the variables in the script to your needs (e.g., Slack webhook URL, server name, users to ping).
* Execute the script as sudo user with optional flag to disable webhook.
```
$ sudo ./check-server-updates.sh [no-webhook]
```

### Check app vulnerabilities

This script scans for vulnerabilities in PHP (Composer) and JavaScript (NPM/Yarn) dependencies. It reports findings to a webhook or prints to the console.

This script executes these steps:
* Recursively find projects with composer.json or package.json starting from a specified directory (default: /home).
* Optionally include or exclude projects inside "vendor" or "node_modules" folders.
* For each project, check for the presence and validity of lock files.
* Run security audits using composer audit and npm audit.
* Count vulnerabilities by severity levels (critical, high, medium/moderate, low).
* Generate a summary report with counts and details per project.
* Send the report to a webhook or print it to the console.

To execute this script:
* Adjust the variables in the script to your needs (e.g., Webhook URL, server name, users to ping).
* Execute the script as sudo user with optional parameters for directory and flags.
```
$ sudo ./check-app-vulnerabilities.sh [DIRECTORY] [include-vendor] [include-node-modules] [show-missing-lock-file] [no-webhook]
```

### Check resource usage

This script monitors system resource usage and sends alerts when thresholds are exceeded. Currently monitors disk space usage with plans to expand to CPU, memory, network, and other metrics.

This script executes these steps:
* Check disk space usage on configured partitions (default: / and /home).
* Compare usage against WARNING (default: 80%) and CRITICAL (default: 90%) thresholds.
* Send webhook alerts for partitions exceeding thresholds.
* Implement cooldown period (default: 4 hours) to prevent alert fatigue.
* Log all checks and alerts to /var/log/check-resource-usage.log.
* Skip alerts during cooldown period for the same partition and severity level.

Configuration in `config.sh`:
* `CHECK_RESOURCE_USAGE_DISK_WARNING_THRESHOLD`: Warning threshold percentage (default: 80)
* `CHECK_RESOURCE_USAGE_DISK_CRITICAL_THRESHOLD`: Critical threshold percentage (default: 90)
* `CHECK_RESOURCE_USAGE_PARTITIONS`: Space-separated list of partitions to monitor (default: "/ /home")
* `CHECK_RESOURCE_USAGE_ALERT_COOLDOWN_MINUTES`: Minutes between alerts for same issue (default: 240)

Future metrics (documented in script comments):
* CPU usage monitoring
* Memory (RAM) usage monitoring
* Disk I/O monitoring
* Network usage monitoring
* Load average monitoring
* Process count monitoring
* Swap usage monitoring
* System uptime tracking
* Temperature monitoring

To execute this script:
* Configure thresholds and partitions in config.sh.
* Execute the script as sudo user with optional flag to disable webhook.
* Recommended: Schedule with cron for periodic monitoring (e.g., every 15 minutes).
```
$ sudo ./check-resource-usage.sh [no-webhook]
```

Example cron job for monitoring every 15 minutes:
```
*/15 * * * * /path/to/check-resource-usage.sh
```

## Todo
* Use sshpass to make the remote certificates backup.
* Make optional the verbose configuration.
* Make an option to delete the remote and the local backups.
* Compress the SQL dump.

## License
[GNU Affero General Public License v3 or higher](https://www.gnu.org/licenses/agpl-3.0.en.html)