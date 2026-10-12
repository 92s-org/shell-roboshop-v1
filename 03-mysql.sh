#!/bin/bash

R="\e[31m"
G="\e[32m"
Y="\e[33m"
N="\e[0m"
user_id=$(id -u)

scripts_dir=$(dirname "$(realpath "$0")")   # folder of this script, works from any directory
script_name=$(basename "$0" .sh)           # 03-mysql.sh -> 03-mysql
logs_folder="/var/log/roboshop"
logs_file="$logs_folder/$script_name.log"
start_time=$(date +%s)
mysql_root_password="RoboShop@1"
timestamp(){
    date "+%Y-%m-%d %H:%M:%S"
}

if [ $user_id -ne 0 ]; then
    echo -e "$(timestamp) [ERROR] $R Please run this script with root access $N"
    exit 1
fi

mkdir -p $logs_folder
chown -R ec2-user:ec2-user $logs_folder
chmod -R 755 $logs_folder
echo -e "$(timestamp) [INFO] ===== $script_name started =====" | tee -a "$logs_file"

VALIDATE(){
    if [ $1 -ne 0 ]; then
        echo -e "$(timestamp) [ERROR] $2 ... ${R}FAILURE${N}" | tee -a "$logs_file"
        exit 1
    else
        echo -e "$(timestamp) [INFO] $2 ... ${G}SUCCESS${N}" | tee -a "$logs_file"
    fi
}

dnf module enable mysql:8.4 -y &>> "$logs_file"
VALIDATE $? "Enabling MySQL 8.4"

dnf install mysql-server -y &>> "$logs_file"
VALIDATE $? "Installing MySQL Server"

systemctl enable --now mysqld &>> "$logs_file"
VALIDATE $? "Starting and enabling MySQL"

# Known error: on a re-run the password is already set, and mysql -uroot without it fails.
# So first try logging in with the password. If that works, skip.
mysql -uroot -p"$mysql_root_password" -e "SELECT 1;" &>> "$logs_file"
if [ $? -ne 0 ]; then
    mysql -uroot -e "
    ALTER USER 'root'@'localhost' IDENTIFIED BY '$mysql_root_password';
    CREATE USER IF NOT EXISTS 'root'@'%' IDENTIFIED BY '$mysql_root_password';
    GRANT ALL PRIVILEGES ON *.* TO 'root'@'%' WITH GRANT OPTION;
    " &>> "$logs_file"
    VALIDATE $? "Setting root password"
else
    echo -e "$(timestamp) [INFO] Root password already set ... ${Y}SKIPPING${N}" | tee -a "$logs_file"
fi

end_time=$(date +%s)
echo -e "$(timestamp) [INFO] ===== $script_name completed in ${G}$((end_time - start_time)) seconds${N} =====" | tee -a "$logs_file"