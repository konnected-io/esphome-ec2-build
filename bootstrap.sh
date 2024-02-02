#!/bin/bash

sudo yum install -y python3.11
sudo yum install -y git
python3.11 -m ensurepip --upgrade
pip3 install --no-input wheel
pip3 install --no-input esphome
mkdir esphome-configs
wget https://raw.githubusercontent.com/konnected-io/esphome-ec2-build/main/build.sh
chmod +x build.sh