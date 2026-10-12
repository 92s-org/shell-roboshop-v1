#!/bin/bash

R="\e[31m"
G="\e[32m"
Y="\e[33m"
N="\e[0m"
user_id=$(id -u)
 
scripts_dir=$(dirname "$(realpath "$0")")   # folder of this script, works from any directory
script_name=$(basename "$0" .sh)           # 01-mongodb.sh -> 01-mongodb
logs_folder="/var/log/roboshop"
logs_file="$logs_folder/$script_name.log"
start_time=$(date +%s)
timestamp=$(date "+%Y-%m-%d %H:%M:%S")

if [ $user_id -ne 0 ]; then
    echo -e "$timestamp [ERROR] $R Please run this script with root access $N"
    exit 1
fi

mkdir -p $logs_folder
chown -R ec2-user:ec2-user $logs_folder
chmod -R 755 $logs_folder

VALIDATE(){
    if [ $1 -ne 0 ]; then
        echo -e "$timestamp [ERROR] $2 ... $R FAILURE $N" | tee -a $logs_file
        exit 1
    else
        echo -e "$timestamp [INFO] $2 ... $G SUCCESS $N" | tee -a $logs_file
    fi
}

cp "$scripts_dir/mongo.repo" /etc/yum.repos.d/mongo.repo
VALIDATE $? "Adding Mongo repo"

dnf install mongodb-org -y &>> $logs_file
VALIDATE $? "Installing MongoDB"

systemctl enable --now mongod
VALIDATE $? "Starting and enabling MongoDB"

sed -i 's/127.0.0.1/0.0.0.0/g' /etc/mongod.conf
VALIDATE $? "Allowing remote connections to MongoDB"

systemctl restart mongod
VALIDATE $? "Restarting MongoDB"

PING=$(mongosh --quiet --eval 'db.runCommand({ ping: 1 }).ok' 2>&1)
echo "ping result: $PING" | LOG
[ "$PING" = "1" ]
VALIDATE $? "MongoDB responds to ping"

end_time=$(date +%s)
echo -e "$timestamp [INFO] ===== $script_name completed in ${G}$((end_time - start_time)) seconds${N} =====" | tee -a "$logs_file"
