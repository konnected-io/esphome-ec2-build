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
This creates an EC2 instance and bootstraps it by installing required Python packages. The ESPHome build will run on this instance. I am still experimenting on what is the optimal instance size for this task. It works on a `t2.micro` and it's eligible for free tier so using this for testing.

```
aws ec2 run-instances                                  \
  --image-id ami-0a3c3a20c09d6f377                     \
  --count 1                                            \
  --instance-type t2.micro                             \
  --key-name esphome-cloud-build-key                   \
  --security-group-ids sg-0de24bf7302c0ac79            \
  --user-data file://bootstrap.sh                      \
  --iam-instance-profile '
      {
        "Name" : "EnablesEC2ToAccessSystemsManagerRole"
      }'
```

Save the Instance ID that is created, you will need it later. View and connect to the instance in AWS Console: EC2 > Instances

### Update SSM Agent

Replace `INSTANCE_ID` below with your newly created EC2 Instance ID and run the command
to update the SSM Agent.

```
aws ssm send-command                                                    \
  --document-name "AWS-UpdateSSMAgent"                                  \
  --document-version "1"                                                \
  --targets '[{"Key":"InstanceIds","Values":["INSTANCE_ID"]}]'          \
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
Add a Target to the EventBridge Rule to kick off the build script on the EC2 instance. If you
later replace the instance, just edit `rule-target.json` and run this command again to point
the EventBridge Rule to the new instance.

Replace `INSTANCE_ID` in `rule-target.json` with your EC2 Instance ID.

```
aws events put-targets --cli-input-json file://rule-target.json
```
