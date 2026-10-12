#!/bin/bash

R="\e[31m"
G="\e[32m"
Y="\e[33m"
N="\e[0m"
user_id=$(id -u)

scripts_dir=$(dirname "$(realpath "$0")")   # folder of this script, works from any directory
script_name=$(basename "$0" .sh)           # 05-catalogue.sh -> 05-catalogue
logs_folder="/var/log/roboshop"
logs_file="$logs_folder/$script_name.log"
start_time=$(date +%s)
app_name="catalogue"
domain_name="daws92s.store"                  # change this for your domain
mongodb_host="mongodb.$domain_name"
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

dnf module disable nodejs -y &>> "$logs_file"
VALIDATE $? "Disabling default NodeJS"

dnf module enable nodejs:24 -y &>> "$logs_file"
VALIDATE $? "Enabling NodeJS 24"

dnf install nodejs -y &>> "$logs_file"
VALIDATE $? "Installing NodeJS"

# Known error: on a re-run the user already exists and useradd fails. So check first.
id roboshop &>> "$logs_file"
if [ $? -ne 0 ]; then
    useradd --system --home /app --shell /sbin/nologin --comment "roboshop system user" roboshop &>> "$logs_file"
    VALIDATE $? "Creating roboshop system user"
else
    echo -e "$(timestamp) [INFO] System user roboshop already exists ... ${Y}SKIPPING${N}" | tee -a "$logs_file"
fi

# Remove old code so a re-run always deploys a clean copy
rm -rf /app
VALIDATE $? "Removing old code"

mkdir -p /app
VALIDATE $? "Creating app directory"

# -f: fail on HTTP errors like 404, -L: follow redirects
curl -fL -o /tmp/$app_name.zip https://raw.githubusercontent.com/daws-92s/roboshop-documentation/refs/heads/main/artifacts/$app_name-v4.zip &>> "$logs_file"
VALIDATE $? "Downloading $app_name code"

cd /app
VALIDATE $? "Moving to app directory"

unzip /tmp/$app_name.zip &>> "$logs_file"
VALIDATE $? "Extracting $app_name code"

npm install &>> "$logs_file"
VALIDATE $? "Installing dependencies"

cp "$scripts_dir/$app_name.service" /etc/systemd/system/$app_name.service
VALIDATE $? "Copying $app_name service file"

sed -i "s/DOMAIN_NAME/$domain_name/g" /etc/systemd/system/$app_name.service
VALIDATE $? "Updating domain name in service file"

systemctl daemon-reload
VALIDATE $? "Reloading systemd"

cp "$scripts_dir/mongo.repo" /etc/yum.repos.d/mongo.repo
VALIDATE $? "Adding Mongo repo"

dnf install mongodb-mongosh -y &>> "$logs_file"
VALIDATE $? "Installing MongoDB client"

# Load master data only once: loading again adds the products twice
product_count=$(mongosh --host $mongodb_host --quiet --eval 'db.getSiblingDB("catalogue").products.countDocuments()' 2>> "$logs_file")
VALIDATE $? "Connecting to MongoDB"

if [ "$product_count" -eq 0 ]; then
    mongosh --host $mongodb_host </app/db/master-data.js &>> "$logs_file"
    VALIDATE $? "Loading master data"
else
    echo -e "$(timestamp) [INFO] Master data already loaded ($product_count products) ... ${Y}SKIPPING${N}" | tee -a "$logs_file"
fi

systemctl enable $app_name &>> "$logs_file"
VALIDATE $? "Enabling $app_name"

# restart, not start: on a re-run it picks up the new code and service file
systemctl restart $app_name
VALIDATE $? "Starting $app_name"

sleep 5
curl -sf http://localhost:8080/health &>> "$logs_file"
VALIDATE $? "$app_name health check"

end_time=$(date +%s)
echo -e "$(timestamp) [INFO] ===== $script_name completed in ${G}$((end_time - start_time)) seconds${N} =====" | tee -a "$logs_file"