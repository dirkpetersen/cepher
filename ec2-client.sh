#!/bin/bash

# AWS EC2 Ceph Client Instance Launch Script
#
# This script creates an EC2 instance configured as a Ceph client.
# Supports: NFS, SMB/CIFS, CephFS, S3/RadosGW, iSCSI, NVMe-oF
#
# Usage: ./ec2-client.sh

# Configuration Variables
: "${AWS_REGION:="us-west-2"}"
: "${EC2_TYPE:="c6a.xlarge"}"    # arm a1.medium, c8gd.xlarge x86:t3a.small x86 with disk: c6id.large, i3.large
: "${AMI_ARM:="ami-03be04a3da3a40226"}"  # Rocky Linux 9 ARM64
: "${AMI_X86:="ami-0fadb4bc4d6071e9e"}"  # Rocky Linux 9 x86_64
: "${ROOT_VOLUME_SIZE:="20"}"
: "${INSTANCE_NAME:="ceph-client"}" 
: "${DOMAIN:="ai.oregonstate.edu"}"
: "${CLOUD_INIT_FILE:="ec2-client-cloud-init.txt"}"
: "${EC2_USER:="rocky"}"
: "${EC2_SECURITY_GROUPS:="SSH-HTTP-ICMP ceph-cluster-sg ceph-client-sg"}"

# Auto-detect AMI based on instance type architecture if AMI_IMAGE not explicitly set
if [[ -z "${AMI_IMAGE:-}" ]]; then
    # Get instance type architecture from AWS
    INSTANCE_ARCH=$(aws ec2 describe-instance-types \
        --instance-types "${EC2_TYPE}" \
        --region "${AWS_REGION}" \
        --query 'InstanceTypes[0].ProcessorInfo.SupportedArchitectures[0]' \
        --output text 2>/dev/null)
    
    case "${INSTANCE_ARCH}" in
        "arm64")
            AMI_IMAGE="${AMI_ARM}"
            echo "Detected ARM64 architecture for ${EC2_TYPE}, using AMI: ${AMI_IMAGE}"
            ;;
        "x86_64")
            AMI_IMAGE="${AMI_X86}"
            echo "Detected x86_64 architecture for ${EC2_TYPE}, using AMI: ${AMI_IMAGE}"
            ;;
        *)
            echo "Warning: Could not detect architecture for ${EC2_TYPE}, defaulting to x86_64"
            AMI_IMAGE="${AMI_X86}"
            ;;
    esac
else
    echo "Using explicitly set AMI_IMAGE: ${AMI_IMAGE}"
fi

FQDN="${INSTANCE_NAME}.${DOMAIN}"

# Check AWS authentication
if ! aws sts get-caller-identity &>/dev/null; then
    echo "Error: AWS CLI not authenticated. Run 'aws sso login --no-browser'"
    exit 1
fi

# Set up SSH key variables
identity_info=$(aws sts get-caller-identity --query '[Account, Arn]' --output text)
AWSACCOUNT=$(echo "$identity_info" | awk '{print $1}')
AWSUSER=$(echo "$identity_info" | awk '{print $2}' | awk -F'/' '{print $NF}')
AWSUSER2="${AWSUSER%@*}"
: "${EC2_KEY_NAME:="auto-ec2-${AWSUSER}"}"
: "${EC2_KEY_FILE:="~/.ssh/auto-ec2-${AWSACCOUNT}-${AWSUSER2}.pem"}"
EC2_KEY_FILE=$(eval echo "${EC2_KEY_FILE}")

# Check if instance already exists
echo "Checking for existing client instance: ${INSTANCE_NAME}..."
INSTANCE_ID=$(aws ec2 describe-instances \
    --filters "Name=tag:Name,Values=${INSTANCE_NAME}" "Name=instance-state-name,Values=pending,running" \
    --query "Reservations[].Instances[0].InstanceId" \
    --output text 2>/dev/null)

if [[ "$INSTANCE_ID" != "None" && -n "$INSTANCE_ID" ]]; then
    echo "Found existing instance: ${INSTANCE_ID}"
else
    echo "Creating new client instance..."
    
    # Resolve security groups to IDs
    SG_IDS=()
    for sg_name in ${EC2_SECURITY_GROUPS}; do
        sg_id=$(aws ec2 describe-security-groups \
            --filters "Name=group-name,Values=${sg_name}" \
            --query 'SecurityGroups[0].GroupId' \
            --output text 2>/dev/null)
        if [[ "$sg_id" == "None" || -z "$sg_id" ]]; then
            echo "Error: Security group '${sg_name}' not found"
            exit 1
        fi
        SG_IDS+=("$sg_id")
        echo "✓ ${sg_name} -> ${sg_id}"
    done
    
    # Launch instance
    userdata_param=""
    [[ -f "${CLOUD_INIT_FILE}" ]] && userdata_param="--user-data file://${CLOUD_INIT_FILE}"
    
    INSTANCE_ID=$(aws ec2 run-instances \
        --image-id ${AMI_IMAGE} \
        --count 1 \
        --instance-type ${EC2_TYPE} \
        --key-name ${EC2_KEY_NAME} \
        --security-group-ids ${SG_IDS[*]} \
        --block-device-mappings "[{\"DeviceName\":\"/dev/sda1\",\"Ebs\":{\"VolumeSize\":${ROOT_VOLUME_SIZE}}}]" \
        ${userdata_param} \
        --tag-specifications "ResourceType=instance,Tags=[{Key=Name,Value=${INSTANCE_NAME}}]" \
        --query 'Instances[0].InstanceId' \
        --output text)
    
    if [[ -z "$INSTANCE_ID" ]]; then
        echo "Error: Failed to launch instance"
        exit 1
    fi
    echo "Launched instance: ${INSTANCE_ID}"
fi

# Wait for instance to be running and get IPs
echo "Waiting for instance to be ready..."
while true; do
    instance_info=$(aws ec2 describe-instances --instance-ids ${INSTANCE_ID} \
        --query 'Reservations[0].Instances[0].{State:State.Name,PublicIp:PublicIpAddress,PrivateIp:PrivateIpAddress}' \
        --output json)
    
    STATE=$(echo "$instance_info" | jq -r '.State')
    PUBLIC_IP=$(echo "$instance_info" | jq -r '.PublicIp // ""')
    PRIVATE_IP=$(echo "$instance_info" | jq -r '.PrivateIp // ""')
    
    if [[ "$STATE" == "running" && -n "$PUBLIC_IP" && "$PUBLIC_IP" != "null" ]]; then
        echo "Instance is running: ${PUBLIC_IP}"
        break
    fi
    echo "Instance state: ${STATE}, waiting..."
    sleep 10
done

# Wait for SSH
echo "Waiting for SSH access..."
for i in {1..30}; do
    if ssh -i "${EC2_KEY_FILE}" -o ConnectTimeout=5 -o StrictHostKeyChecking=no \
        ${EC2_USER}@${PUBLIC_IP} exit 2>/dev/null; then
        echo "SSH is ready"
        break
    fi
    [[ $i -eq 30 ]] && { echo "SSH timeout"; exit 1; }
    sleep 10
done

# Always set hostname (idempotent operation)
echo "Setting hostname to ${INSTANCE_NAME}..."
SHORT_NAME="${FQDN%%.*}"
ssh -i "${EC2_KEY_FILE}" -o StrictHostKeyChecking=no ${EC2_USER}@${PUBLIC_IP} "
    sudo hostnamectl set-hostname ${SHORT_NAME}
    sudo sed -i '/\\s${FQDN}\$/d; /\\s${SHORT_NAME}\$/d' /etc/hosts
    echo '${PRIVATE_IP} ${FQDN} ${SHORT_NAME}' | sudo tee -a /etc/hosts
    echo 'Hostname set to ${SHORT_NAME}'
"

# One-time setup for new instances
if [[ -z "$(aws ec2 describe-tags --filters "Name=resource-id,Values=${INSTANCE_ID}" "Name=key,Values=SetupComplete" --query 'Tags[0].Value' --output text 2>/dev/null)" ]]; then
    echo "First-time setup - packages installed via cloud-init"
    aws ec2 create-tags --resources ${INSTANCE_ID} --tags Key=SetupComplete,Value=true
else
    echo "Instance packages already configured"
fi

# Register DNS if Route53 available
HOSTED_ZONE_ID=$(aws route53 list-hosted-zones --query 'HostedZones[0].Id' --output text 2>/dev/null)
if [[ "$HOSTED_ZONE_ID" != "None" && -n "$HOSTED_ZONE_ID" ]]; then
    echo "Updating DNS: ${FQDN} -> ${PUBLIC_IP}"
    aws route53 change-resource-record-sets --hosted-zone-id ${HOSTED_ZONE_ID} \
        --change-batch "{\"Changes\":[{\"Action\":\"UPSERT\",\"ResourceRecordSet\":{\"Name\":\"${FQDN}\",\"Type\":\"A\",\"TTL\":300,\"ResourceRecords\":[{\"Value\":\"${PUBLIC_IP}\"}]}}]}" >/dev/null
fi

# Output summary
EC2_KEY_FILE2=$(echo $EC2_KEY_FILE | sed "s|$HOME|~|")
echo
echo "=== Ceph Client Ready ==="
echo "Instance: ${INSTANCE_ID}"
echo "FQDN: ${FQDN}"
echo "Public IP: ${PUBLIC_IP}"
echo "Private IP: ${PRIVATE_IP}"
echo
echo "Supported protocols: NFS, SMB/CIFS, CephFS, S3/RadosGW, iSCSI, NVMe-oF"
echo
echo "ssh -i ${EC2_KEY_FILE2} ${EC2_USER}@${FQDN}"
echo
