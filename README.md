# Minecraft-Server-BASH-Scripts
A collection of scripts and services for managing a Minecraft server on a custom server or on an AWS instance.

## minecraft.sh
A BASH script which controls installing and managing a Minecraft server on a Linux system.
### Installation
Initial download and install be achieved by running the following commands:

```Bash
curl https://raw.githubusercontent.com/DrakoTrogdor/Minecraft-Server-BASH-Script/HEAD/minecraft.sh > ~/minecraft.sh
chmod +x ~/minecraft.sh
sudo ~/minecraft.sh install
```
### Usage
After installation a symbolic link from /usr/bin/mc to the minecraft.sh script is setup. 

- mc start  -  Start the Minecraft server.
- mc stop   -  Stop the Minecraft server.
- mc restart  -  Restart the Minecraft server.
- mc status  -  Retrieve the status of the Minecraft server service.
- mc instances  -  List all Mincraft server service instances.
- mc enable  -  Enable this Mincraft server service instance.
- mc disable  -  Disable this Mincraft server service instance.
- mc update  -  Update PaperMC to the latest version.
- mc connect  -  Connect to the Minecraft server console.
- mc reload  -  Send the \"reload\" command to the Minecraft server.
- mc send  -  Send command to the Minecraft server. This accepts any minecraft command for the OPTION argument.
- mc listen  -  Show console history. This updates as the console is updated.
- mc logs  -  View the latest server log.
- mc fixperms  -  Fix file permissions for the Minecraft server folder and sub folders.
- mc install  -  Setup and configure a new instance of PaperMC using the latest version in the current folder.
- mc fetch  -  Fetches the latest version of this script.
- mc backup  -  Backup the current server.

## aws_instance_start.sh / aws_instance_start.service
A BASH script and systemd service unit file for changing the Elastic IP allocation at start up as well as updating an IPv6 address on a GoDaddy registered domain.
### Installation
Initial download and install be achieved by running the following commands:

```Bash
curl https://raw.githubusercontent.com/DrakoTrogdor/Minecraft-Server-BASH-Script/HEAD/aws_instance_start.sh > ~/aws_instance_start.sh
curl https://raw.githubusercontent.com/DrakoTrogdor/Minecraft-Server-BASH-Script/HEAD/aws_instance_start.sh > ~/aws_instance_start.service
chmod +x ~/aws_instance_start.sh
sudo systemctl enable ~/aws_instance_start.service
```
A configuration file must be created at ~/aws_instance_start.conf with the following lines:
```Bash
eip_ID="eipalloc-0123456789abcdef0"         # YOUR Elastic IP address.
key="abcdefghijklmnopqrstuvwxyz012345678"   # YOUR key for godaddy developer API.
secret="abcdefghijklmnopqrstuv"             # YOUR secret for godaddy developer API.
domain="domain.tld"                         # YOUR domain.
name="@"                                    # YOUR record name to update. 
```

### Usage
After installation this script will run automatically at server start-up.  This is useful for AWS Spot Instances that are set to NOT delete the volume after termination.  Attach the volume to a new spot instance and it will automatically configure the IPv4 and IPv6 addresses.
If the addresses need to be manually set, this can be done with:

```Bash
~/aws_instance_start.sh
```
## aws_instance_stop.sh / aws_instance_stop.service
A BASH script and systemd service unit file for sending an SMS text message to a pre-determined phone number when the instance is shut down.
### Installation
Initial download and install be achieved by running the following commands:

```Bash
curl https://raw.githubusercontent.com/DrakoTrogdor/Minecraft-Server-BASH-Script/HEAD/aws_instance_stop.sh > ~/aws_instance_stop.sh
curl https://raw.githubusercontent.com/DrakoTrogdor/Minecraft-Server-BASH-Script/HEAD/aws_instance_stop.sh > ~/aws_instance_stop.service
chmod +x ~/aws_instance_stop.sh
sudo systemctl enable ~/aws_instance_stop.service
```
A configuration file must be created at ~/aws_instance_start.conf with the following lines:
```Bash
server_Name="Descriptive server name"       # YOUR server name.
notify_Target="+18001234567"                # YOUR phone number.
```

### Usage
After installation this script will run automatically at server start-up and wait for server shut-down (this does not cause any resource usage other than the running of the scripts).  This is useful for AWS Spot Instances that are set to NOT delete the volume after termination.  A message will be sent notifying the user that the instance is going down.
If a test is desired one of the following commands can be execute:

```Bash
~/aws_instance_start.sh
sudo systemctl restart aws_instance_stop.service
```

## aws_instance_request.sh
A BASH script for requesting a new spot fleet instance request.
### Installation
Initial download and install be achieved by running the following commands:

```Bash
curl https://raw.githubusercontent.com/DrakoTrogdor/Minecraft-Server-BASH-Script/HEAD/aws_instance_request.sh > ~/aws_instance_request.sh
chmod +x aws_instance_request.sh
```
A configuration file must be created at ~/aws_instance_start with the following lines:
```Bash
server_Name="Descriptive server name"                                                                                     # YOUR server name.
ec2_iamFleetRole='arn:aws:iam::000123456789:role/aws-service-role/spotfleet.amazonaws.com/AWSServiceRoleForEC2SpotFleet'  # YOUR IAM Fleet Role ARN.
ec2_instanceType='m5.xlarge'                                                                                              # Desired Instance Type string.
ec2_keyPairName='KeyPair Descriptive Name'                                                                                # YOUR EC2 Key Pair Name.
ec2_securityGroupID='sg-0123456789abcdefgh'                                                                               # YOUR VPC Security Group ID.
ec2_subnetID='subnet-0123456789abcdefg'                                                                                   # YOUR VPC Subnet ID.
ec2_availabilityZone='us-east-1a'                                                                                         # YOUR desired Availability Zone string.
ec2_spotMaxTotalPrice='0.300'                                                                                             # YOUR desired Maximum Total Spot Price.
```

### Usage
After downloading this script execute it by running the following:

```Bash
~/aws_instance_start.sh
```

_**Note:** If any commands do not work for you, it may be because elevated permissions are required, try using `sudo <command> [args]` instead._
