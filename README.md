# ESPHome EC2 Cloud Build 
Quickly and cheaply build ESPHome firmware in the cloud using AWS EC2 and S3.

[AWS Tutorial](https://aws.amazon.com/getting-started/hands-on/remotely-run-commands-ec2-instance-systems-manager/)

## Setup

### Clone this repo
Clone this repo (or a fork) on to your local machine, then run the following commands from the root of the project.

### Create a Role
Create an IAM role that will be used to give Systems Manager permission to perform actions on your instances.
Follow _Step 1_ in [this tutorial](https://aws.amazon.com/getting-started/hands-on/remotely-run-commands-ec2-instance-systems-manager/).

### Create a Key Pair
(optional) If you want to be able to ssh into the instance, create a Key Pair in the AWS Console: EC2 > Network & Security > Key Pairs. Name the key pair `esphome-cloud-build-key` and download the private key.

### Create EC2 Instance
Create a settings file for each environment by copying `environments/example.env` to `environments/<env>.env` (e.g. `dev.env`, `prod.env`) and filling in the AWS account ID, instance type, key pair name and `KONNECTED_ENV`. These files are gitignored.

A small Graviton instance such as `t4g.micro` (1 GB RAM plus the swap that bootstrap adds) is enough for low-traffic use. Use a larger one such as `c8g.large` for faster builds.

Then launch an instance with `launch.sh`, using AWS credentials for that environment's account:

```
./launch.sh dev
```

This launches the latest Amazon Linux 2023 (arm64/Graviton) AMI and bootstraps it with `bootstrap.sh`, which installs Python 3.12 and ESPHome, writes `~/.env` for the environment, and installs `build.sh` and `update-esphome.sh`. Bootstrap output is logged to `/var/log/cloud-init-output.log` on the instance.

The new instance is tagged `esphome-cloud-build=staging` so it does not receive builds until it's promoted (see [Replace an instance](#replace-an-instance)). Save the Instance ID that it prints.

### Update SSM Agent

```
aws ssm send-command                                                    \
  --document-name "AWS-UpdateSSMAgent"                                  \
  --document-version "1"                                                \
  --targets '[{"Key":"tag:esphome-cloud-build","Values":["build"]}]'          \
  --cloud-watch-output-config '{"CloudWatchOutputEnabled":true,"CloudWatchLogGroupName":"esphome-cloud-build"}'
```

### Enable EventBridge on S3
Enable EventBridge on your S3 bucket so that events start firing whenever new files are created.
Replace `BUCKET` with your S3 bucket name.

```
aws s3api put-bucket-notification-configuration                       \
  --bucket BUCKET                                                     \
  --notification-configuration='{ "EventBridgeConfiguration": {} }'

```

### Create EventBridge Rule
The EventBridge rule responds to Object Created events and then runs the build command on the EC2 instance.
Replace `BUCKET` with your S3 bucket name.

```
aws events put-rule --name esphome-cloud-build-start                                        \
  --description "Kicks off an ESPHome firmware compile when a config file is placed in S3"  \
  --state ENABLED                                                                           \
  --event-pattern '
    {
      "source": ["aws.s3"],
      "detail-type": ["Object Created"],
      "detail": {
        "bucket": {
          "name": ["BUCKET"]
        }
      }
    }'                                                                                      \
```

### Create/update Target Instance
Add a Target to the EventBridge Rule to kick off the build script on the EC2 instance identified by tags.

Replace `ACCOUNT_ID` in `rule-target.json` with your AWS Account ID.

```
aws events put-targets --cli-input-json file://rule-target.json
```

### Create a Maintenance Window to update ESPHome periodically
The maintenance window runs `update-esphome.sh`, which upgrades ESPHome and **fails** if the installed version is still behind PyPI (for example, when a new ESPHome release requires a newer Python than the instance has). If that happens, bump `PYTHON` in `bootstrap.sh` and replace the instance.

```
aws ssm create-maintenance-window  \
  --name "Update_ESPHome" \
  --schedule "rate(2 days)" \
  --duration 1 \
  --cutoff 0

aws ssm register-target-with-maintenance-window \
  --window-id <mw-from-above>  \
  --resource-type "INSTANCE" \
  --name "esphome-cloud-build" \
  --targets "Key=tag:esphome-cloud-build,Values=build"

aws ssm register-task-with-maintenance-window \
  --window-id <mw-from-above>  \
  --task-type "RUN_COMMAND"  \
  --task-arn "AWS-RunShellScript"  \
  --targets "Key=WindowTargetIds,Values=<window-target-id-from-above>" \
  --max-concurrency 1 --max-errors 1 \
  --service-role-arn "arn:aws:iam::<ACCOUNT_ID>:role/aws-service-role/ssm.amazonaws.com/AWSServiceRoleForAmazonSSM"  \
  --task-invocation-parameters '
      {
        "RunCommand": {
            "Parameters": {
                "commands": ["runuser -l ec2-user -c ./update-esphome.sh"],
                "executionTimeout": ["600"]
            },
            "TimeoutSeconds": 600
        }
      }'
```

Point the task at the tag-based window target (as above), not at an instance ID, so replacing the instance doesn't require updating the maintenance window.

To switch an existing task from an instance ID to the window target:
```
aws ssm update-maintenance-window-task --window-id <mw-id> --window-task-id <task-id> \
  --targets "Key=WindowTargetIds,Values=<window-target-id>" \
  --task-invocation-parameters '{"RunCommand":{"Parameters":{"commands":["runuser -l ec2-user -c ./update-esphome.sh"],"executionTimeout":["600"]},"TimeoutSeconds":600}}'
```

### Replace an instance
1. Launch a new instance with `./launch.sh <env>`. It's tagged `staging`, so it won't receive builds yet.
2. SSH in and check it: `cloud-init status` shows `done`, `esphome version` shows the latest ESPHome, and `./update-esphome.sh` succeeds. Compile a config with `esphome compile` to test it.
3. Promote the new instance and demote the old one. Builds and the maintenance window target the `build` tag, so don't leave both instances tagged `build` or every upload will build twice. SSM can take a few minutes to see the tag change, so builds may not reach either instance for a short time.
   ```
   aws ec2 create-tags --resources <new-instance-id> --tags Key=esphome-cloud-build,Value=build
   aws ec2 create-tags --resources <old-instance-id> --tags Key=esphome-cloud-build,Value=retired
   aws ec2 stop-instances --instance-ids <old-instance-id>
   ```
4. Once the new instance has handled real builds for a few days, terminate the old one.
