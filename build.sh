#!/bin/bash

bucket=$1
key=$2
regex="^esphome-configs\/(konnected-[0-9a-f]+)\.([0-9]+)\.yaml$"

if [[ $key =~ $regex ]]
then

  {
  name="${BASH_REMATCH[1]}"
  version="${BASH_REMATCH[2]}"
  aws s3 cp s3://${bucket}/${key} ${key}
  echo "Building ${name} v${version} ~~"
  esphome compile ${key}
  fw_path=~/esphome-configs/.esphome/build/${name}/.pioenvs/${name}
  aws s3 cp ${fw_path}/firmware.bin s3://${bucket}/esphome-builds/${name}.${version}.ota.bin 
  aws s3 cp ${fw_path}/firmware-factory.bin s3://${bucket}/esphome-builds/${name}.${version}.0x0.bin
  } 2>&1

fi