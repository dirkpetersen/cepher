#!/bin/bash

# Show help if requested
if [[ "$1" == "-h" || "$1" == "--help" ]]; then
    echo "Ceph Client Security Group Creation Script"
    echo ""
    echo "Usage: $0 [vpc-id]"
    echo ""
    echo "Arguments:"
    echo "  vpc-id          VPC ID where the security group will be created"
    echo ""
    echo "Environment Variables:"
    echo "  VPC_ID          VPC ID (alternative to command line argument)"
    echo "  SG_NAME         Security group name (default: ceph-client-sg)"
    echo "  SG_DESCRIPTION  Security group description"
    echo "  AWS_REGION      AWS region (default: us-west-2)"
    echo ""
    echo "Examples:"
    echo "  $0 vpc-0123456789abcdef0"
    echo "  VPC_ID=vpc-0123456789abcdef0 $0"
    echo "  AWS_REGION=us-east-1 VPC_ID=vpc-0123456789abcdef0 $0"
    exit 0
fi

# Parse command line arguments
VPC_ID_ARG=""
if [[ $# -eq 1 ]]; then
    VPC_ID_ARG="$1"
elif [[ $# -gt 1 ]]; then
    echo "Usage: $0 [vpc-id]"
    echo "  vpc-id: VPC ID (can also be set via VPC_ID environment variable)"
    echo ""
    echo "Examples:"
    echo "  $0 vpc-0123456789abcdef0"
    echo "  VPC_ID=vpc-0123456789abcdef0 $0"
    exit 1
fi

# Determine VPC ID (command line argument takes precedence over environment variable)
if [[ -n "$VPC_ID_ARG" ]]; then
    VPC_ID="$VPC_ID_ARG"
elif [[ -n "${VPC_ID}" ]]; then
    # Use environment variable if set
    VPC_ID="${VPC_ID}"
else
    echo "Error: VPC ID must be provided either as:"
    echo "  1. Command line argument: $0 vpc-0123456789abcdef0"
    echo "  2. Environment variable: VPC_ID=vpc-0123456789abcdef0 $0"
    exit 1
fi

# Validate VPC ID format
if [[ ! "$VPC_ID" =~ ^vpc-[0-9a-f]{8,17}$ ]]; then
    echo "Error: Invalid VPC ID format. Expected format: vpc-xxxxxxxxx"
    echo "Provided: $VPC_ID"
    exit 1
fi

# Variables - Can be overridden by environment variables
: "${SG_NAME:="ceph-client-sg"}"
: "${SG_DESCRIPTION:="Security Group for Ceph Client Access (NFS, SMB, CephFS, S3, iSCSI, NVMe-oF)"}"
: "${AWS_REGION:="us-west-2"}"
REGION="${AWS_REGION}"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${YELLOW}Creating Ceph Client Security Group...${NC}"
echo -e "VPC ID: ${GREEN}$VPC_ID${NC}"
echo -e "Region: ${GREEN}$REGION${NC}"
echo -e "Security Group Name: ${GREEN}$SG_NAME${NC}"

# Verify VPC exists
echo -e "${YELLOW}Verifying VPC exists...${NC}"
if ! aws ec2 describe-vpcs --vpc-ids "$VPC_ID" --region "$REGION" >/dev/null 2>&1; then
    echo -e "${RED}Error: VPC $VPC_ID not found in region $REGION${NC}"
    echo -e "${YELLOW}To list available VPCs:${NC}"
    echo -e "${GREEN}aws ec2 describe-vpcs --region $REGION --query 'Vpcs[].{VpcId:VpcId,Name:Tags[?Key==\`Name\`].Value|[0]}' --output table${NC}"
    exit 1
fi
echo -e "${GREEN}✓ VPC $VPC_ID found${NC}"

# Check if security group already exists
echo -e "${YELLOW}Checking if security group already exists...${NC}"
EXISTING_SG_ID=$(aws ec2 describe-security-groups \
    --filters "Name=group-name,Values=$SG_NAME" "Name=vpc-id,Values=$VPC_ID" \
    --region "$REGION" \
    --query 'SecurityGroups[0].GroupId' \
    --output text 2>/dev/null)

if [[ "$EXISTING_SG_ID" != "None" && -n "$EXISTING_SG_ID" ]]; then
    echo -e "${YELLOW}Security group '$SG_NAME' already exists with ID: $EXISTING_SG_ID${NC}"
    echo -e "${YELLOW}Do you want to add missing rules to the existing security group? (y/N)${NC}"
    read -r response
    if [[ "$response" =~ ^[Yy]$ ]]; then
        SG_ID="$EXISTING_SG_ID"
        echo -e "${GREEN}Using existing security group: $SG_ID${NC}"
    else
        echo -e "${RED}Aborting. Please choose a different name or delete the existing security group.${NC}"
        exit 1
    fi
else
    # Create the security group
    echo -e "${YELLOW}Creating new security group...${NC}"
    SG_ID=$(aws ec2 create-security-group \
        --group-name "$SG_NAME" \
        --description "$SG_DESCRIPTION" \
        --vpc-id "$VPC_ID" \
        --region "$REGION" \
        --query 'GroupId' \
        --output text)

    if [ $? -eq 0 ]; then
        echo -e "${GREEN}Security Group created successfully: $SG_ID${NC}"
    else
        echo -e "${RED}Failed to create security group${NC}"
        exit 1
    fi
fi

# Add tags to the security group
echo -e "${YELLOW}Adding tags to security group...${NC}"
if aws ec2 create-tags \
    --resources "$SG_ID" \
    --tags Key=Name,Value="$SG_NAME" Key=Purpose,Value="Ceph Client Access" \
    --region "$REGION" 2>/dev/null; then
    echo -e "${GREEN}✓ Tags added successfully${NC}"
else
    echo -e "${YELLOW}⚠ Could not add tags (insufficient permissions, but security group still functional)${NC}"
fi

echo -e "${YELLOW}Adding ingress rules for client access...${NC}"

# Function to add ingress rule from anywhere (0.0.0.0/0)
add_public_ingress_rule() {
    local port=$1
    local protocol=$2
    local description=$3
    local error_output
    
    error_output=$(aws ec2 authorize-security-group-ingress \
        --group-id "$SG_ID" \
        --protocol "$protocol" \
        --port "$port" \
        --cidr "0.0.0.0/0" \
        --region "$REGION" 2>&1)
    
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}✓ Added rule: $description (Port: $port) - Public access${NC}"
    else
        if echo "$error_output" | grep -q "InvalidPermission.Duplicate"; then
            echo -e "${YELLOW}⚠ Rule already exists: $description (Port: $port)${NC}"
        else
            echo -e "${RED}✗ Failed to add rule: $description (Port: $port)${NC}"
            echo -e "${RED}  Error: $error_output${NC}"
        fi
    fi
}

# Function to add port range rule from anywhere
add_public_port_range_rule() {
    local from_port=$1
    local to_port=$2
    local protocol=$3
    local description=$4
    local error_output
    
    error_output=$(aws ec2 authorize-security-group-ingress \
        --group-id "$SG_ID" \
        --protocol "$protocol" \
        --port "$from_port-$to_port" \
        --cidr "0.0.0.0/0" \
        --region "$REGION" 2>&1)
    
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}✓ Added rule: $description (Ports: $from_port-$to_port) - Public access${NC}"
    else
        if echo "$error_output" | grep -q "InvalidPermission.Duplicate"; then
            echo -e "${YELLOW}⚠ Rule already exists: $description (Ports: $from_port-$to_port)${NC}"
        else
            echo -e "${RED}✗ Failed to add rule: $description (Ports: $from_port-$to_port)${NC}"
            echo -e "${RED}  Error: $error_output${NC}"
        fi
    fi
}

# SSH for management
add_public_ingress_rule "22" "tcp" "SSH management"

# NFS client access
add_public_ingress_rule "2049" "tcp" "NFS"
add_public_ingress_rule "111" "tcp" "NFS portmapper"
add_public_ingress_rule "111" "udp" "NFS portmapper UDP"

# SMB/CIFS client access
add_public_ingress_rule "445" "tcp" "SMB/CIFS"
add_public_ingress_rule "139" "tcp" "NetBIOS Session Service"
add_public_ingress_rule "137" "udp" "NetBIOS Name Service"
add_public_ingress_rule "138" "udp" "NetBIOS Datagram Service"

# S3 RadosGW client access
add_public_ingress_rule "80" "tcp" "HTTP (S3/RGW)"
add_public_ingress_rule "443" "tcp" "HTTPS (S3/RGW)"
add_public_ingress_rule "7480" "tcp" "Ceph RGW HTTP"
add_public_ingress_rule "7481" "tcp" "Ceph RGW HTTPS"

# iSCSI client access
add_public_ingress_rule "3260" "tcp" "iSCSI target"
add_public_port_range_rule "860" "861" "tcp" "iSCSI additional ports"

# NVMe-oF (NVMe over TCP) client access  
add_public_ingress_rule "4420" "tcp" "NVMe-oF TCP default"
add_public_port_range_rule "4420" "4430" "tcp" "NVMe-oF TCP range"

# CephFS direct client access (for ceph-fuse and kernel client)
# Note: CephFS clients need to connect to MON and OSD ports
add_public_ingress_rule "3300" "tcp" "Ceph Monitor (new default)"
add_public_ingress_rule "6789" "tcp" "Ceph Monitor (legacy)"
add_public_port_range_rule "6800" "7300" "tcp" "Ceph OSD/MGR/MDS services"

# Add ICMP for ping/troubleshooting
error_output=$(aws ec2 authorize-security-group-ingress \
    --group-id "$SG_ID" \
    --protocol "icmp" \
    --port "-1" \
    --cidr "0.0.0.0/0" \
    --region "$REGION" 2>&1)

if [ $? -eq 0 ]; then
    echo -e "${GREEN}✓ Added rule: ICMP for ping/troubleshooting - Public access${NC}"
else
    if echo "$error_output" | grep -q "InvalidPermission.Duplicate"; then
        echo -e "${YELLOW}⚠ Rule already exists: ICMP for ping/troubleshooting${NC}"
    else
        echo -e "${RED}✗ Failed to add rule: ICMP${NC}"
        echo -e "${RED}  Error: $error_output${NC}"
    fi
fi

echo -e "${YELLOW}Summary:${NC}"
echo -e "Security Group ID: ${GREEN}$SG_ID${NC}"
echo -e "Security Group Name: ${GREEN}$SG_NAME${NC}"
echo -e "VPC ID: ${GREEN}$VPC_ID${NC}"
echo -e "Region: ${GREEN}$REGION${NC}"

echo -e "\n${YELLOW}Client protocols supported:${NC}"
echo -e "${GREEN}✓ NFS (Network File System) - Port 2049, 111${NC}"
echo -e "${GREEN}✓ SMB/CIFS - Ports 445, 139, 137, 138${NC}"
echo -e "${GREEN}✓ CephFS - Ports 3300, 6789, 6800-7300${NC}"
echo -e "${GREEN}✓ S3/RadosGW - Ports 80, 443, 7480, 7481${NC}"
echo -e "${GREEN}✓ iSCSI - Port 3260, 860-861${NC}"
echo -e "${GREEN}✓ NVMe-oF - Ports 4420-4430${NC}"

echo -e "\n${YELLOW}To attach this security group to your Ceph client, use:${NC}"
echo -e "${GREEN}aws ec2 modify-instance-attribute --instance-id <instance-id> --groups $SG_ID --region $REGION${NC}"

echo -e "\n${YELLOW}To view the security group rules:${NC}"
echo -e "${GREEN}aws ec2 describe-security-groups --group-ids $SG_ID --region $REGION${NC}"

echo -e "\n${GREEN}Ceph client security group setup completed!${NC}"