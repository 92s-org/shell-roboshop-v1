#!/bin/bash

R="\e[31m"
G="\e[32m"
Y="\e[33m"
N="\e[0m"
user_id=$(id -u)

scripts_dir=$(dirname "$(realpath "$0")")   # folder of this script, works from any directory
script_name=$(basename "$0" .sh)           # 04-rabbitmq.sh -> 04-rabbitmq
logs_folder="/var/log/roboshop"
logs_file="$logs_folder/$script_name.log"
start_time=$(date +%s)
rabbitmq_user="roboshop"
rabbitmq_password="roboshop123"
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

cp "$scripts_dir/rabbitmq.repo" /etc/yum.repos.d/rabbitmq.repo
VALIDATE $? "Adding RabbitMQ repo"

dnf install erlang rabbitmq-server -y &>> "$logs_file"
VALIDATE $? "Installing Erlang and RabbitMQ"

systemctl enable --now rabbitmq-server &>> "$logs_file"
VALIDATE $? "Starting and enabling RabbitMQ"

# Known error: on a re-run the user already exists and add_user fails.
# So first check if the user is there. If yes, skip.
rabbitmqctl list_users --silent | grep -qw "^$rabbitmq_user"
if [ $? -ne 0 ]; then
    rabbitmqctl add_user "$rabbitmq_user" "$rabbitmq_password" &>> "$logs_file"
    VALIDATE $? "Creating RabbitMQ user $rabbitmq_user"
else
    echo -e "$(timestamp) [INFO] RabbitMQ user $rabbitmq_user already exists ... ${Y}SKIPPING${N}" | tee -a "$logs_file"
fi

# set_permissions is safe to re-run, it just sets the same permissions again
rabbitmqctl set_permissions -p / "$rabbitmq_user" ".*" ".*" ".*" &>> "$logs_file"
VALIDATE $? "Setting permissions for $rabbitmq_user"

end_time=$(date +%s)
echo -e "$(timestamp) [INFO] ===== $script_name completed in ${G}$((end_time - start_time)) seconds${N} =====" | tee -a "$logs_file"