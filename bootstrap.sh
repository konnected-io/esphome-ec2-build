#!/bin/bash

sudo yum install -y python3.11
python3.11 -m ensurepip --upgrade
pip3 install --no-input wheel
pip3 install --no-input esphome
mkdir esphome-configs
