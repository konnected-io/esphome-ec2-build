#!/bin/bash

bucket=$1
key=$2
regex="^esphome-configs\/(.+)\.yaml$"

echo $bucket
echo $key

if [[ $key =~ $regex ]]
then

  {
  name="${BASH_REMATCH[1]}"
  aws s3 cp s3://${bucket}/${key} ${key}
  esphome compile ${key}
  aws s3 cp /tmp/build/.pioenvs/${name}/firmware.bin s3://${bucket}/esphome-builds/${name}-OTA.bin 
  aws s3 cp /tmp/build/.pioenvs/${name}/firmware-factory.bin s3://${bucket}/esphome-builds/${name}-full.bin
  } 2>&1

fi