#!/bin/bash

R="\e[31m"
G="\e[32m"
Y="\e[33m"
N="\e[0m"
user_id=$(id -u)

scripts_dir=$(dirname "$(realpath "$0")")   # folder of this script, works from any directory
script_name=$(basename "$0" .sh)           # 02-redis.sh -> 02-redis
logs_folder="/var/log/roboshop"
logs_file="$logs_folder/$script_name.log"
start_time=$(date +%s)
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

dnf module disable redis -y &>> "$logs_file"
VALIDATE $? "Disabling default Redis"

dnf module enable redis:7 -y &>> "$logs_file"
VALIDATE $? "Enabling Redis 7"

dnf install redis -y &>> "$logs_file"
VALIDATE $? "Installing Redis"

sed -i -e 's/^bind 127.0.0.1/bind 0.0.0.0/' -e 's/^protected-mode yes/protected-mode no/' /etc/redis/redis.conf
VALIDATE $? "Allowing remote connections to Redis"

systemctl enable --now redis
VALIDATE $? "Starting and enabling Redis"

systemctl restart redis
VALIDATE $? "Restarting Redis"

end_time=$(date +%s)
echo -e "$(timestamp) [INFO] ===== $script_name completed in ${G}$((end_time - start_time)) seconds${N} =====" | tee -a "$logs_file"