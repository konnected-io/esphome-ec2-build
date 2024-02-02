#!/bin/bash

yum install -y python3.11
yum install -y git
python3.11 -m ensurepip --upgrade
runuser -l ec2-user -c 'pip3 install --no-input wheel'
runuser -l ec2-user -c 'pip3 install --no-input esphome'
runuser -l ec2-user -c 'mkdir esphome-configs'
runuser -l ec2-user -c 'wget https://raw.githubusercontent.com/konnected-io/esphome-ec2-build/main/build.sh'
runuser -l ec2-user -c 'chmod +x build.sh'