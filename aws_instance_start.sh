#!/usr/bin/bash
#In order for this script to work the command "aws configure" needs to be run as root
#Setup a systemd service with the following unit file:
#  [Unit]
#  Description=Adjust IPv4 and IPv6 addresses at startup
#  Wants=network-online.target
#  After=network-online.target
#
#  [Service]
#  ExecStart=/opt/minecraft/aws_instance_start.sh
#
#  [Install]
#  WantedBy=multi-user.target
#
#
#Setup the following details for in a seperate file named aws_instance_start.conf stored in the same directory as this script:
#  eip_ID="eipalloc-0123456789abcdef0"         # YOUR Elastic IP address.
#  key="abcdefghijklmnopqrstuvwxyz012345678"   # YOUR key for godaddy developer API.
#  secret="abcdefghijklmnopqrstuv"             # YOUR secret for godaddy developer API.
#  domain="domain.tld"                         # YOUR domain.
#  name="@"                                    # YOUR record name to update. 
SCRIPT=$(readlink -f "${BASH_SOURCE[0]}")
SCRIPTFILE=$(basename "$SCRIPT")
SCRIPTFILEONLY=${SCRIPTFILE%%.sh}
SCRIPTPATH=$(dirname "$SCRIPT")
readonly CONFIG_FILE="${SCRIPTPATH}/${SCRIPTFILEONLY}.conf"
echo "Loading private details from \"${CONFIG_FILE}\"..."
source ${CONFIG_FILE}

#Additional configuration settings:
type="AAAA"                                 # Record type A, CNAME, MX, etc.
ttl="600"                                   # Time to Live min value 600
port="1"                                    # Required port, Min value 1
weight="1"                                  # Required weight, Min value 1

sleep 10s #Wait 10s due to allocated_InstanceID not being set for a second or two.
#Set the Elastic IP address to this server.
current_IP=$(ip -4 addr show dev eth0|grep -Eo 'inet\s*(addr:)?\s*([0-9]{1,3}\.){3}[0-9]{1,3}'|grep -Eo '([0-9]{1,3}\.){3}[0-9]{1,3}'|grep -v '127.0.0.1')
TOKEN=$(curl -X PUT "http://169.254.169.254/latest/api/token" -H "X-aws-ec2-metadata-token-ttl-seconds: 21600")
current_InstanceID=$(curl -H "X-aws-ec2-metadata-token: $TOKEN" -s http://169.254.169.254/latest/meta-data/instance-id) && echo "current_InstanceID = ${current_InstanceID}"
allocated_InstanceID=$(aws ec2 describe-addresses --allocation-ids ${eip_ID}|jq -r .Addresses[0].InstanceId) && echo "allocated_InstanceID = ${allocated_InstanceID}"
if [[ ${allocated_InstanceID} == ${current_InstanceID} ]]; then
    echo "The Elastic IP \"${eip_ID}\" is already allocated to this instance \"${current_InstanceID}\""
else
    aws ec2 associate-address --instance-id ${current_InstanceID} --allocation-id eipalloc-077d82ee854889d3d
    echo "The Elastic IP \"${eip_ID}\" has been allocated to this instance \"${current_InstanceID}\""
fi

#Update the IPv6 address on GoDaddy
headers="Authorization: sso-key $key:$secret"

ipv6_godaddy=$(curl -s -X GET -H "$headers" -H "Content-Type: application/json" "https://api.godaddy.com/v1/domains/$domain/records/$type/$name"|jq -r .[0].data) && echo "ipv6_godaddy:" $ipv6_godaddy
ipv6_local=$(ip -6 addr show dev eth0|grep -Eo 'inet6\s*(addr:)?\s*([0-9a-fA-F]{1,4}[:]{1,2}){1,7}([0-9a-fA-F]{1,4}){0,1}'|grep -Eo '([0-9a-fA-F]{1,4}[:]{1,2}){1,7}([0-9a-fA-F]{1,4}){0,1}'|grep -v ^::1 | grep -v ^fe80) && echo "ipv6_local:" $ipv6_local
if [[ ${ipv6_godaddy} == ${ipv6_local} ]]; then
    echo "Local and GoDaddy IPv6 addresses are already equal, no update required"
else
    echo "Local and GoDaddy IPv6 addresses are not equal, updating the GoDaddy record..."
    curl -X PUT "https://api.godaddy.com/v1/domains/$domain/records/$type/$name" \
        -H "accept: application/json" \
        -H "Content-Type: application/json" \
        -H "$headers" \
        -d "[ { \"data\": \"$ipv6_local\", \"port\": $port, \"priority\": 0, \"protocol\": \"string\", \"service\": \"string\", \"ttl\": $ttl, \"weight\": $weight } ]"  
fi
