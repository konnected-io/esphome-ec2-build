#!/bin/bash
# Launches a new ESPHome build instance, bootstrapped with bootstrap.sh.
# Usage: ./launch.sh <env>   (with AWS credentials for that environment's account)
#
# Settings for each environment are read from environments/<env>.env
# (see environments/example.env).
#
# The instance is tagged esphome-cloud-build=staging so it doesn't receive builds
# until it's verified and promoted to esphome-cloud-build=build (see README).
set -euo pipefail

env_file="$(dirname "$0")/environments/${1:-}.env"
if [ -z "${1:-}" ] || [ ! -f "${env_file}" ]
then
  echo "usage: $0 <env>   (requires environments/<env>.env; see environments/example.env)" >&2
  exit 1
fi
source "${env_file}"

current_account=$(aws sts get-caller-identity --query Account --output text)
if [ "${current_account}" != "${ACCOUNT_ID}" ]
then
  echo "AWS credentials are for account ${current_account}, but $1 is in ${ACCOUNT_ID}" >&2
  exit 1
fi

# latest Amazon Linux 2023 for Graviton (arm64)
ami=$(aws ssm get-parameter                                                   \
  --name /aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-arm64 \
  --query Parameter.Value --output text)

aws ec2 run-instances                                                           \
  --image-id "${ami}"                                                           \
  --count 1                                                                     \
  --instance-type "${INSTANCE_TYPE}"                                            \
  --key-name "${KEY_NAME}"                                                      \
  --user-data "$(sed "s/__KONNECTED_ENV__/${KONNECTED_ENV}/" "$(dirname "$0")/bootstrap.sh")" \
  --iam-instance-profile Name=EnablesEC2ToAccessSystemsManagerRole              \
  --metadata-options HttpTokens=required                                        \
  --block-device-mappings '[{"DeviceName":"/dev/xvda","Ebs":{"VolumeSize":30,"VolumeType":"gp3"}}]' \
  --tag-specifications "[{\"ResourceType\":\"instance\",\"Tags\":[{\"Key\":\"esphome-cloud-build\",\"Value\":\"staging\"},{\"Key\":\"Name\",\"Value\":\"esphome-cloud-build-$1\"}]}]" \
  --query 'Instances[0].InstanceId' --output text
