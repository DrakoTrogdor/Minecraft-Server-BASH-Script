#!/bin/bash
#Setup the following details for in a seperate file named aws_instance_request.conf stored in the same directory as this script:
#  server_Name="Descriptive server name"                                                                                     # YOUR server name.
#  ec2_iamFleetRole='arn:aws:iam::000123456789:role/aws-service-role/spotfleet.amazonaws.com/AWSServiceRoleForEC2SpotFleet'  # YOUR IAM Fleet Role ARN.
#  ec2_instanceType='m5.xlarge'                                                                                              # Desired Instance Type string.
#  ec2_keyPairName='KeyPair Descriptive Name'                                                                                # YOUR EC2 Key Pair Name.
#  ec2_securityGroupID='sg-0123456789abcdefgh'                                                                               # YOUR VPC Security Group ID.
#  ec2_subnetID='subnet-0123456789abcdefg'                                                                                   # YOUR VPC Subnet ID.
#  ec2_availabilityZone='us-east-1a'                                                                                         # YOUR desired Availability Zone string.
#  ec2_spotMaxTotalPrice='0.300'                                                                                             # YOUR desired Maximum Total Spot Price.
SCRIPT=$(readlink -f "${BASH_SOURCE[0]}")
SCRIPTFILE=$(basename "$SCRIPT")
SCRIPTFILEONLY=${SCRIPTFILE%%.sh}
SCRIPTPATH=$(dirname "$SCRIPT")
readonly CONFIG_FILE="${SCRIPTPATH}/${SCRIPTFILEONLY}.conf"
echo "Loading private details from \"${CONFIG_FILE}\"..."
source ${CONFIG_FILE}

#Display all current Instance Types between 4 and 8 vCPUs, between 16384 and 32768 MB RAM, and with x86_64 architecture sorted by vCPU, RAM, Name

echo "Do you want to select a new instance type (${ec2_instanceType})? [y|n]."
while true; do
    read -n 1 -s -r -p ":" response
    case $response in
        [Yy])
            filtered_instance_types=$(aws ec2 describe-instance-types|jq -r ".InstanceTypes[]|select(.MemoryInfo.SizeInMiB>=16384 and .MemoryInfo.SizeInMiB<=32768 and .VCpuInfo.DefaultVCpus>=4 and .VCpuInfo.DefaultVCpus<=8)|select(.ProcessorInfo.SupportedArchitectures[]==\"x86_64\")|\"\(.InstanceType)\t\t\(.ProcessorInfo.SupportedArchitectures[])\t\t\(.VCpuInfo.DefaultVCpus) vCPUs\t\t\(.MemoryInfo.SizeInMiB) MB\""|sort -k3,3 -k5,5 -k1,1 )
            oldcols=$COLUMNS;COLUMNS=24;IFS=$'\n';select resp in $filtered_instance_types;do echo "Choice: \"${resp}\"";break;done;IFS=;COLUMNS=$oldcols;unset oldcols
            ec2_instanceType=$(echo $resp|cut -f1)
            echo "Do you want to proceed with your new instance type (${ec2_instanceType})? [y|n]."
            while true; do
                read -n 1 -s -r -p ":" response
                case $response in
                    [Yy])
                        break
                        ;;
                    [Nn])
                        exit 0
                        ;;
                esac
            done
            break
            ;;
        [Nn])
            break
            ;;
    esac
done
current_Date=$(date +"%Y-%m-%d")
current_Time=$(date +"%H:%M:%S")
current_DateTime="${current_Date}@${current_Time}"
object_FullName="${server_Name} - ${current_DateTime}"
object_SafeName=$(echo $object_FullName|sed -E 's/v([0-9]+)\.([0-9]+)\.([0-9]+)/v\1\2\3/g'|sed 's/[:\-]//g'|sed 's/[^A-Za-z0-9_\-]/_/g'|sed 's/__/_/g')

#Create new snapshot from latest volume
ec2_volumeID=$(aws ec2 describe-volumes|jq -r ".Volumes|=sort_by(.CreateTime)|.[]|reverse|.[]|select(.Tags != null)|select(.Tags[].Key == \"Server\")|select(.Tags[].Value == \"${server_Name}\")|.VolumeId")
ec2_createSnapshotJSON="{
    \"Description\":\"${server_Name} - ${current_DateTime}\",
    \"VolumeId\":\"${ec2_volumeID}\",
    \"TagSpecifications\":[
        {
            \"ResourceType\":\"snapshot\",
            \"Tags\":[
                {
                    \"Key\":\"Name\",
                    \"Value\":\"${object_SafeName}\"
                },
                {
                    \"Key\":\"Server\",
                    \"Value\":\"${server_Name}\"
                },
                {
                    \"Key\":\"Date\",
                    \"Value\":\"${current_DateTime}\"
                }
            ]
        }
    ]
}"
ec2_snapshot=$(aws ec2 create-snapshot --cli-input-json "${ec2_createSnapshotJSON}") && echo $ec2_snapshot
ec2_snapshotID=$(echo $ec2_snapshot|jq -r .SnapshotId)

#Create new AMI Image
aws ec2 wait snapshot-completed --snapshot-ids ${ec2_snapshotID} #Wait for the snapshow to complete creation
ec2_snapshotSize=$(echo $ec2_snapshot|jq -r .VolumeSize)
ec2_registerImageJSON="{
    \"Architecture\":\"x86_64\",
    \"BlockDeviceMappings\":[
        {
            \"DeviceName\":\"/dev/sda1\",
            \"Ebs\":{
                \"DeleteOnTermination\":false,
                \"SnapshotId\":\"${ec2_snapshotID}\",
                \"VolumeSize\":${ec2_snapshotSize},
                \"VolumeType\":\"gp2\"
            }
        }
    ],
    \"Description\":\"${server_Name} - ${current_DateTime}\",
    \"Name\":\"${object_SafeName}\",
    \"RootDeviceName\":\"/dev/sda1\"
}"
ec2_image=$(aws ec2 register-image --cli-input-json "${ec2_registerImageJSON}") && echo $ec2_image
ec2_imageID=$(echo $ec2_image|jq -r .ImageId)

#Add tags to the new AMI Image
ec2_imageTags="{
    \"Resources\":[
        \"${ec2_imageID}\"
    ],
    \"Tags\":[
        {
            \"Key\":\"Name\",
            \"Value\":\"${object_SafeName}\"
        },
        {
            \"Key\":\"Server\",
            \"Value\":\"${server_Name}\"
        },
        {
            \"Key\":\"Date\",
            \"Value\":\"${current_DateTime}\"
        }
    ]
}"
aws ec2 create-tags --cli-input-json "${ec2_imageTags}"

#Create Spot Fleet Request
ec2_createSpotFleetRequestJSON="{
    \"SpotFleetRequestConfig\": {
        \"AllocationStrategy\":\"lowestPrice\",
        \"ExcessCapacityTerminationPolicy\":\"default\",
        \"IamFleetRole\":\"${ec2_iamFleetRole}\",
        \"InstanceInterruptionBehavior\":\"terminate\",
        \"InstancePoolsToUseCount\":1,
        \"LaunchSpecifications\":[
            {
                \"ImageId\":\"${ec2_imageID}\",
                \"InstanceType\":\"${ec2_instanceType}\",
                \"KeyName\":\"${ec2_keyPairName}\",
                \"NetworkInterfaces\":[
                    {
                        \"AssociatePublicIpAddress\":true,
                        \"DeleteOnTermination\":true,
                        \"DeviceIndex\":0,
                        \"Groups\":[
                            \"${ec2_securityGroupID}\"
                        ],
                        \"SubnetId\":\"${ec2_subnetID}\"
                    }
                ],
                \"Placement\":{
                    \"AvailabilityZone\":\"${ec2_availabilityZone}\",
                    \"Tenancy\":\"default\"
                },
                \"UserData\":\"\"
            }
        ],
        \"OnDemandAllocationStrategy\":\"lowestPrice\",
        \"OnDemandFulfilledCapacity\":0,
        \"OnDemandTargetCapacity\":0,
        \"ReplaceUnhealthyInstances\":false,
        \"SpotMaxTotalPrice\":\"${ec2_spotMaxTotalPrice}\",
        \"TargetCapacity\":1,
        \"Type\":\"request\"
    }
}"
ec2_spotFleetRequest=$(aws ec2 request-spot-fleet --cli-input-json "${ec2_createSpotFleetRequestJSON}") && echo $ec2_spotFleetRequest
ec2_spotFleetRequestID=$(echo $ec2_spotFleetRequest|jq -r .SpotFleetRequestId)

#wait for the Spot Fleet Request to become active
sleep 5s
ec2_spotFleetRequestStatus=$(aws ec2 describe-spot-fleet-requests --spot-fleet-request-ids "${ec2_spotFleetRequestID}" |jq -r ".SpotFleetRequestConfigs[]|.SpotFleetRequestState") && echo "Spot Fleet Request for \"${ec2_spotFleetRequestID}\" is \"${ec2_spotFleetRequestStatus}\"." || echo "Error requesting status for Spot Fleet Request \"${ec2_spotFleetRequestID}\"."
until [[ ${ec2_spotFleetRequestStatus} == 'active' ]]; do
    sleep 5s
    ec2_spotFleetRequestStatus=$(aws ec2 describe-spot-fleet-requests --spot-fleet-request-ids "${ec2_spotFleetRequestID}" |jq -r ".SpotFleetRequestConfigs[]|.SpotFleetRequestState") && echo "Spot Fleet Request for \"${ec2_spotFleetRequestID}\" is \"${ec2_spotFleetRequestStatus}\"." || echo "Error requesting status for Spot Fleet Request \"${ec2_spotFleetRequestID}\"."
    case $ec2_spotFleetRequestStatus in
        "subitted")
            #Do nothing here...this is why we are waiting.
        ;;
        "active")
            echo -e "\nThe Spot Fleet Request has become active."
        ;;
        "modifying")
            echo -e "\nThe Spot Fleet Request is being modified...exiting script"
            exit 1
            break
        ;;
        "cancelled_running"|"cancelled_terminating"|"cancelled")
            echo -e "\nThe Spot Fleet Request is being cancelled...exiting script"
            exit 1
            break
        ;;
        *)
            echo -e "\nSomething else is going on exiting"
            break
        ;;
    esac
done
ec2_spotFleetInstances=$(aws ec2 describe-spot-fleet-instances --spot-fleet-request-id "${ec2_spotFleetRequestID}"|jq -r .ActiveInstances[0])
if [[ -z ${ec2_spotFleetInstances} ]]; then
    echo "There was an error requesting the Spot Fleet...Exiting!"
    exit 1
fi

#Wait for the Spot Instance to become active
echo "Waiting for the instance to become active"
ec2_spotInstanceRequestID=$(echo $ec2_spotFleetInstances|jq -r .SpotInstanceRequestId)
aws ec2 wait spot-instance-request-fulfilled --spot-instance-request-ids ${ec2_spotInstanceRequestID}

#Find the instance and add the tags
ec2_instanceID=$(echo $ec2_spotFleetInstances|jq -r .InstanceId)
ec2_instanceTags="{
    \"Resources\":[
        \"${ec2_instanceID}\"
    ],
    \"Tags\":[
        {
            \"Key\":\"Name\",
            \"Value\":\"${object_SafeName}\"
        },
        {
            \"Key\":\"Server\",
            \"Value\":\"${server_Name}\"
        },
        {
            \"Key\":\"Date\",
            \"Value\":\"${current_DateTime}\"
        }
    ]
}"
aws ec2 create-tags --cli-input-json "${ec2_instanceTags}"

#Find the volume and add the tags
ec2_newVolumeID=$(aws ec2 describe-instances --instance-ids "${ec2_instanceID}"|jq -r .Reservations[0].Instances[0].BlockDeviceMappings[0].Ebs.VolumeId) && echo $ec2_newVolumeID
ec2_newVolumeTags="{
    \"Resources\":[
        \"${ec2_newVolumeID}\"
    ],
    \"Tags\":[
        {
            \"Key\":\"CreateSnapshot\",
            \"Value\":\"true\"
        },
        {
            \"Key\":\"Name\",
            \"Value\":\"${object_SafeName}\"
        },
        {
            \"Key\":\"Server\",
            \"Value\":\"${server_Name}\"
        },
        {
            \"Key\":\"Date\",
            \"Value\":\"${current_DateTime}\"
        }
    ]
}"
aws ec2 create-tags --cli-input-json "${ec2_newVolumeTags}"
########################################
#Cleanup all image/volume/snapshot time#
########################################
echo "Cleanup of all image/volume/snapshots about to proceed"
echo "Continue [y|n]."
while true; do
    read -n 1 -s -r -p ":" response
    case $response in
        [Yy])
            echo "Proceeding with cleanup."
            break
            ;;
        [Nn])
            echo "Cancelling cleanup."
            exit 0
            ;;
    esac
done
if [[ -z ${ec2_imageID} ]];then
    echo "There is an issue with the Image ID...exiting before deletion"
    exit 1
fi
if [[ -z ${ec2_newVolumeID} ]];then
    echo "There is an issue with the Volume ID...exiting before deletion"
    exit 1
fi
if [[ -z ${ec2_snapshotID} ]];then
    echo "There is an issue with the Snapshot ID...exiting before deletion"
    exit 1
fi
ec2_oldImages=$(aws ec2 describe-images --owners self|jq -r ".Images[]|select(.Tags!=null)|select(.Tags[].Key==\"Server\")|select(.Tags[].Value==\"${server_Name}\")|.ImageId"|grep -v ${ec2_imageID}) && echo $ec2_oldImages
for val in $ec2_oldImages; do
    echo -n "Deregistering Image \"${val}\"..."
    aws ec2 deregister-image --image-id "${val}" && echo "Done." || echo "Failed."
done
ec2_oldVolumes=$(aws ec2 describe-volumes|jq -r ".Volumes[]|select(.Tags!=null)|select(.Tags[].Key==\"Server\")|select(.Tags[].Value==\"${server_Name}\")|.VolumeId"|grep -v ${ec2_newVolumeID}) && echo $ec2_oldVolumes
for val in $ec2_oldVolumes; do
    echo -n "Deleting Volume \"${val}\"..."
    aws ec2 delete-volume --volume-id "${val}" && echo "Done." || echo "Failed."
done
ec2_oldSnapshots=$(aws ec2 describe-snapshots --owner-ids self|jq -r ".Snapshots[]|select(.Tags!=null)|select(.Tags[].Key==\"Server\")|select(.Tags[].Value==\"${server_Name}\")|select(.VolumeId!=\"${ec2_newVolumeID}\")|.SnapshotId"|grep -v ${ec2_snapshotID}) && echo $ec2_oldSnapshots
for val in $ec2_oldSnapshots; do
    echo -n "Deleting Snapshot \"${val}\"..."
    aws ec2 delete-snapshot --snapshot-id "${val}" && echo "Done." || echo "Failed."
done
