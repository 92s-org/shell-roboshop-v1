#!/bin/bash

R="\e[31m"
G="\e[32m"
Y="\e[33m"
N="\e[0m"
user_id=$(id -u)

scripts_dir=$(dirname "$(realpath "$0")")   # folder of this script, works from any directory
script_name=$(basename "$0" .sh)           # 08-shipping.sh -> 08-shipping
logs_folder="/var/log/roboshop"
logs_file="$logs_folder/$script_name.log"
start_time=$(date +%s)
app_name="shipping"
domain_name="daws92s.shop"                  # change this for your domain
mysql_host="mysql.$domain_name"
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

dnf module enable maven:3.9 -y &>> "$logs_file"
VALIDATE $? "Enabling Maven 3.9"

dnf install maven java-25-openjdk-devel -y &>> "$logs_file"
VALIDATE $? "Installing Maven and Java 25"

# Maven also brings Java 21. alternatives --config java asks interactively,
# so in a script we use --set with the Java 25 path instead
java_path=$(ls /usr/lib/jvm/java-25-openjdk-*/bin/java 2>> "$logs_file" | head -1)
alternatives --set java "$java_path" &>> "$logs_file"
VALIDATE $? "Setting Java 25 as default"

java -version 2>&1 | grep -q 'version "25'
VALIDATE $? "Checking java is version 25"

# JAVA_HOME for Maven: in this script now, and in profile.d for every login
export JAVA_HOME=$(dirname $(dirname $(readlink -f /usr/bin/java)))
echo "export JAVA_HOME=$JAVA_HOME" > /etc/profile.d/java.sh
VALIDATE $? "Setting JAVA_HOME to $JAVA_HOME"

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

# First build takes a few minutes: Maven downloads all the libraries
mvn clean package &>> "$logs_file"
VALIDATE $? "Building $app_name with Maven"

mv target/shipping.jar shipping.jar
VALIDATE $? "Moving shipping.jar"

dnf install mysql -y &>> "$logs_file"
VALIDATE $? "Installing MySQL client"

mysql -h $mysql_host -uroot -p"$mysql_root_password" -e "SELECT 1;" &>> "$logs_file"
VALIDATE $? "Connecting to MySQL"

# Known error: on the first run the cities database does not exist, so the count fails.
# Empty or 0 means not loaded yet. The import is ~60 MB, so skip it when it is already there.
city_count=$(mysql -h $mysql_host -uroot -p"$mysql_root_password" -N -e "SELECT COUNT(*) FROM cities.cities;" 2>/dev/null)
if [ -z "$city_count" ] || [ "$city_count" -eq 0 ]; then
    mysql -h $mysql_host -uroot -p"$mysql_root_password" < /app/db/master-data.sql &>> "$logs_file"
    VALIDATE $? "Loading cities master data"
else
    echo -e "$(timestamp) [INFO] Cities already loaded ($city_count cities) ... ${Y}SKIPPING${N}" | tee -a "$logs_file"
fi

# app-user.sql uses CREATE USER IF NOT EXISTS, so it is safe to run every time
mysql -h $mysql_host -uroot -p"$mysql_root_password" < /app/db/app-user.sql &>> "$logs_file"
VALIDATE $? "Creating shipping app user in MySQL"

cp "$scripts_dir/$app_name.service" /etc/systemd/system/$app_name.service
VALIDATE $? "Copying $app_name service file"

sed -i "s/DOMAIN_NAME/$domain_name/g" /etc/systemd/system/$app_name.service
VALIDATE $? "Updating domain name in service file"

systemctl daemon-reload
VALIDATE $? "Reloading systemd"

systemctl enable $app_name &>> "$logs_file"
VALIDATE $? "Enabling $app_name"

# restart, not start: on a re-run it picks up the new code and service file
systemctl restart $app_name
VALIDATE $? "Starting $app_name"

# Spring Boot takes 10-20 seconds to start, so retry for up to 60 seconds
for i in {1..12}; do
    curl -sf http://localhost:8080/actuator/health &>> "$logs_file" && break
    sleep 5
done
curl -sf http://localhost:8080/actuator/health &>> "$logs_file"
VALIDATE $? "$app_name health check"

end_time=$(date +%s)
echo -e "$(timestamp) [INFO] ===== $script_name completed in ${G}$((end_time - start_time)) seconds${N} =====" | tee -a "$logs_file"