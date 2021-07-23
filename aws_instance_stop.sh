#!/bin/bash
#In order for this script to work the command "aws configure" needs to be run as root and your AWS credential key and secret saved.
#Setup a systemd service with the following unit file:
#  [Unit]
#  Description=Adjust IPv4 and IPv6 addresses at startup
#  Wants=network-online.target
#  After=network-online.target
#
#  [Service]
#  Type=oneshot
#  RemainAfterExit=true
#  ExecStop=/opt/minecraft/aws_instance_stop.sh
#
#  [Install]
#  WantedBy=multi-user.target
#
#
#Setup the following details for in a seperate file named aws_instance_stop.conf stored in the same directory as this script:
#  server_Name="Descriptive server name"       # YOUR server name.
#  notify_Target="+18001234567"                # YOUR phone number.
SCRIPT=$(readlink -f "${BASH_SOURCE[0]}")
SCRIPTFILE=$(basename "$SCRIPT")
SCRIPTFILEONLY=${SCRIPTFILE%%.sh}
SCRIPTPATH=$(dirname "$SCRIPT")
readonly CONFIG_FILE="${SCRIPTPATH}/${SCRIPTFILEONLY}.conf"
echo "Loading private details from \"${CONFIG_FILE}\"..."
source ${CONFIG_FILE}

full_Message="System Halt: ${server_Name} - $(date +"%Y-%m-%d@%H:%M:%S")"
echo "Sending Message: \"${full_Message}\""
echo "Message Target: \"${notify_Target}\""
#ec2_snsMessage="{
#    \"TopicArn\": \"\",
#    \"TargetArn\": \"\",
#    \"PhoneNumber\": \"\",
#    \"Message\": \"\",
#    \"Subject\": \"\",
#    \"MessageStructure\": \"\",
#    \"MessageAttributes\": {
#        \"KeyName\": {
#            \"DataType\": \"\",
#            \"StringValue\": \"\",
#            \"BinaryValue\": null
#        }
#    }
#}"
ec2_snsMessage="{
    \"PhoneNumber\":\"${notify_Target}\",
    \"Message\":\"${full_Message}\"
}"
aws sns publish --cli-input-json "${ec2_snsMessage}"
