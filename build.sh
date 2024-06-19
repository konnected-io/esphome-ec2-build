#!/bin/bash

bucket=$1
key=$2
regex="^esphome-configs\/(konnected-[0-9a-f]+)\.([0-9]+)\.yaml$"

# load .env
set -o allexport
source .env 
set +o allexport

if [[ $key =~ $regex ]]
then

  name="${BASH_REMATCH[1]}"
  version="${BASH_REMATCH[2]}"
  aws s3 cp s3://${bucket}/${key} ${key}
  echo "Building ${name} v${version} with ESPHome $(esphome version) ~~"
  
  # Run the ESPHome build and capture colorized output
  script --flush --quiet --return /tmp/${name}.${version}.log.txt --command "esphome compile ${key}"
  
  if [ $? -eq 0 ]
  then
    fw_path=~/esphome-configs/.esphome/build/${name}/.pioenvs/${name}
    aws s3 cp ${fw_path}/firmware.ota.bin s3://${bucket}/esphome-builds/${name}.${version}.ota.bin 
    aws s3 cp ${fw_path}/firmware.factory.bin s3://${bucket}/esphome-builds/${name}.${version}.0x0.bin
    rm -rf ~/esphome-configs/.esphome/build/${name}
  else    
    base64_log=$(cat /tmp/${name}.${version}.log.txt | base64)
    payload="{\"name\":\"${name}\", \"version\":\"${version}\", \"error\":\"$(echo $base64_log)\"}"
    aws lambda invoke --function-name konnected-cloud-${KONNECTED_ENV}-esphome_build_job-failure \
      --cli-binary-format base64 \
      --payload "$(echo $payload | base64)" \
      /dev/null
  fi
  aws s3 cp /tmp/${name}.${version}.log.txt s3://${bucket}/esphome-logs/${name}.${version}.log.txt

fi