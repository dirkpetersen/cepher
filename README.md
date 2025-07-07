# Ceph Cluster Deployment Toolkit

This repository contains a comprehensive set of shell scripts for automating the deployment and management of Ceph storage clusters on AWS EC2 infrastructure.

## Overview

The toolkit provides end-to-end automation for:
- AWS EC2 instance provisioning with proper security groups
- EBS volume management and attachment
- Ceph cluster bootstrapping and node orchestration
- Cross-host SSH key distribution and file management
- Ceph client deployment with multi-protocol support
- Lambda-based monitoring and cleanup functions

## AWS IAM Permissions Required

### Minimum Required Permissions

The toolkit requires the following AWS IAM permissions to deploy and manage Ceph clusters:

```json
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Sid": "EC2InstanceManagement",
            "Effect": "Allow",
            "Action": [
                "ec2:DescribeInstances",
                "ec2:DescribeInstanceTypes",
                "ec2:DescribeImages",
                "ec2:RunInstances",
                "ec2:TerminateInstances",
                "ec2:CreateTags",
                "ec2:DescribeTags",
                "ec2:ModifyInstanceAttribute"
            ],
            "Resource": "*"
        },
        {
            "Sid": "EBSVolumeManagement",
            "Effect": "Allow",
            "Action": [
                "ec2:CreateVolume",
                "ec2:DeleteVolume",
                "ec2:AttachVolume",
                "ec2:DetachVolume",
                "ec2:DescribeVolumes",
                "ec2:ModifyVolume"
            ],
            "Resource": "*"
        },
        {
            "Sid": "SecurityGroupManagement",
            "Effect": "Allow",
            "Action": [
                "ec2:CreateSecurityGroup",
                "ec2:DeleteSecurityGroup",
                "ec2:DescribeSecurityGroups",
                "ec2:AuthorizeSecurityGroupIngress",
                "ec2:AuthorizeSecurityGroupEgress",
                "ec2:RevokeSecurityGroupIngress",
                "ec2:RevokeSecurityGroupEgress"
            ],
            "Resource": "*"
        },
        {
            "Sid": "NetworkingAndKeyPairs",
            "Effect": "Allow",
            "Action": [
                "ec2:DescribeVpcs",
                "ec2:DescribeSubnets",
                "ec2:DescribeKeyPairs",
                "ec2:CreateKeyPair",
                "ec2:DeleteKeyPair",
                "ec2:ImportKeyPair",
                "ec2:DescribeAvailabilityZones"
            ],
            "Resource": "*"
        },
        {
            "Sid": "Route53DNSManagement",
            "Effect": "Allow",
            "Action": [
                "route53:ListHostedZones",
                "route53:ChangeResourceRecordSets",
                "route53:GetChange"
            ],
            "Resource": "*"
        },
        {
            "Sid": "IAMAndSTSAccess",
            "Effect": "Allow",
            "Action": [
                "sts:GetCallerIdentity",
                "iam:GetUser",
                "iam:ListAccessKeys"
            ],
            "Resource": "*"
        }
    ]
}
```

### Optional Lambda Permissions

For Lambda-based monitoring and cleanup functions:

```json
{
    "Sid": "LambdaManagement",
    "Effect": "Allow",
    "Action": [
        "lambda:CreateFunction",
        "lambda:DeleteFunction",
        "lambda:UpdateFunctionCode",
        "lambda:UpdateFunctionConfiguration",
        "lambda:InvokeFunction",
        "lambda:ListFunctions",
        "iam:CreateRole",
        "iam:DeleteRole",
        "iam:AttachRolePolicy",
        "iam:DetachRolePolicy",
        "iam:PassRole",
        "events:PutRule",
        "events:DeleteRule",
        "events:PutTargets",
        "events:RemoveTargets"
    ],
    "Resource": "*"
}
```

### AWS CLI Authentication Setup

#### Option 1: AWS SSO (Recommended)

```bash
# Configure AWS SSO
aws configure sso

# Login when needed (scripts will prompt automatically)
aws sso login --no-browser
```

#### Option 2: IAM User with Access Keys

```bash
# Configure with access keys
aws configure

# Or set environment variables
export AWS_ACCESS_KEY_ID="your-access-key"
export AWS_SECRET_ACCESS_KEY="your-secret-key"
export AWS_DEFAULT_REGION="us-west-2"
```

#### Option 3: IAM Instance Profile

For running on EC2 instances, attach an IAM role with the above permissions.

### IAM Policy Creation Example

Create a custom IAM policy for the toolkit:

```bash
# Create policy file
cat > ceph-toolkit-policy.json << 'EOF'
{
    "Version": "2012-10-17",
    "Statement": [
        # ... (paste the permissions JSON above)
    ]
}
EOF

# Create IAM policy
aws iam create-policy \
    --policy-name CephToolkitPolicy \
    --policy-document file://ceph-toolkit-policy.json

# Attach to user
aws iam attach-user-policy \
    --user-name your-username \
    --policy-arn arn:aws:iam::YOUR-ACCOUNT:policy/CephToolkitPolicy
```

### Permission Verification

Test your AWS permissions before deployment:

```bash
# Test basic EC2 access
aws ec2 describe-instances --max-items 1

# Test instance type query (for AMI auto-detection)
aws ec2 describe-instance-types --instance-types t3.medium

# Test security group access
aws ec2 describe-security-groups --max-items 1

# Test EBS access
aws ec2 describe-volumes --max-items 1

# Test Route53 access (optional)
aws route53 list-hosted-zones
```

### EC2 SSH Key pair creation 

Cepther will expect a SSH key with this naming convention:  `/.ssh/auto-ec2-<AWS_ACCOUNT_NO>-<IAM_USER>.pem`
The easist way to create such a key is to use the 'ec2' helper script: 

```
mkdir ~/bin && cd  ~/bin 
wget https://raw.githubusercontent.com/dirkpetersen/dptests/refs/heads/main/ec2
wget https://raw.githubusercontent.com/dirkpetersen/dptests/refs/heads/main/ec2-cloud-init.txt
chmod +x ec2 
ec2 list
```

### Security Best Practices

- **Principle of Least Privilege**: Only grant minimum required permissions
- **Use IAM Roles**: Prefer IAM roles over access keys when possible
- **Temporary Credentials**: Use AWS SSO or assume-role for temporary access
- **Resource Constraints**: Add resource-level constraints where appropriate
- **Regular Audits**: Review and rotate credentials regularly

## Core Scripts

### 🚀 Main Deployment Scripts

#### `ec2-create-instances.sh`
**Primary cluster deployment orchestrator**

Creates and configures AWS EC2 instances for Ceph cluster deployment.

**Key Features:**
- **Instance Management**: Discovers existing instances, launches missing ones
- **Storage Configuration**: Attaches configurable EBS volumes (currently 7x 125GB ST1)
- **Network Setup**: Configures security groups with automatic SSH self-access rules
- **DNS Integration**: Registers Route 53 A records for cluster nodes
- **Ceph Orchestration**: Bootstraps first node, then adds additional nodes to cluster

**Usage:**
```bash
# Launch 3-node cluster (auto-detects AMI based on EC2_TYPE)
INSTANCE_NAME=ceph-cluster ./ec2-create-instances.sh 3

# Launch single node  
INSTANCE_NAME=ceph-cluster ./ec2-create-instances.sh 1

# Use x86_64 instance type (auto-selects x86_64 AMI)
INSTANCE_NAME=ceph-cluster EC2_TYPE="t3.large" ./ec2-create-instances.sh 3

# Use ARM64 instance type (auto-selects ARM64 AMI)
INSTANCE_NAME=ceph-cluster EC2_TYPE="c8gd.large" ./ec2-create-instances.sh 3

# Override with custom AMI
INSTANCE_NAME=ceph-cluster AMI_IMAGE="ami-custom123" ./ec2-create-instances.sh 3
```

**Configuration (Environment Variables):**
- `INSTANCE_NAME=ceph-test` - Cluster name 
- `AWS_REGION="us-west-2"` - AWS region
- `EC2_TYPE="i3.4xlarge"` - Instance type (i3.4xlarge/c8gd.large/c5ad.large/c7gd.medium)
- `AMI_ARM="ami-03be04a3da3a40226"` - Rocky Linux 9 ARM64 AMI  
- `AMI_X86="ami-0fadb4bc4d6071e9e"` - Rocky Linux 9 x86_64 AMI
- `AMI_IMAGE` - Override AMI (auto-detected from instance type if not set)
- `EC2_SECURITY_GROUPS="SSH-HTTP-ICMP ceph-cluster-sg"` - Security groups
- `EBS_QTY="6"` - Number of EBS volumes per instance
- `EBS_SIZE="125"` - Size of each EBS volume (GB)
- `EBS_TYPE="st1"` - EBS volume type (st1/gp3/io2)

**AMI Auto-Detection:**
The script automatically selects the correct AMI based on instance type architecture:
- ARM64 instances (c8gd.*, a1.*, etc.) → Uses `AMI_ARM`
- x86_64 instances (t3.*, m5.*, etc.) → Uses `AMI_X86`
- Set `AMI_IMAGE` to override auto-detection

#### `bootstrap-node.sh`
**Ceph cluster bootstrap and node management**

Handles Ceph cluster initialization and node integration with intelligent device detection.

**Operational Modes:**
- **`first`** - Bootstrap new Ceph cluster (MON node)
- **`others`** - Prepare additional nodes for cluster joining
- **`join_cluster`** - Add nodes to existing cluster via orchestrator
- **`create_osds`** - Create Object Storage Daemons on target hosts

**Key Features:**
- **Smart Device Detection**: Retry mechanism with intelligent analysis
  - Distinguishes between available, in-use, and rejected devices
  - Stops retrying permanently rejected devices (partition tables, size issues)
  - Continues retrying for legitimate timing issues on new nodes
- **Comprehensive Status Reporting**: Detailed device analysis and error messages
- **HDD/SSD Optimization**: Configurable ratios for shared DB/WAL on SSDs
- **Cluster Integration**: Waits for proper orchestrator connectivity

NOTE: `bootstrap-node.sh`  will normally be called by ec2-create-instances.sh or a similar script 

**Usage:**
```bash
# Bootstrap first node
sudo bash bootstrap-node.sh first

# Prepare additional node
sudo bash bootstrap-node.sh others

# Add node to cluster (run from first node)
sudo TARGET_HOSTNAME=ceph-test-2 TARGET_INTERNAL_IP=10.0.1.100 bash bootstrap-node.sh join_cluster

# Create OSDs (run from first node)  
sudo TARGET_HOSTNAME=ceph-test-2 bash bootstrap-node.sh create_osds
```

### 🖥️ Client Deployment Scripts

#### `ec2-client.sh`  
**Ceph client instance deployment**

Creates and configures a dedicated EC2 instance as a Ceph client with support for multiple access protocols.

**Key Features:**
- **Multi-Protocol Support**: NFS, SMB/CIFS, CephFS, S3/RadosGW, iSCSI, NVMe-oF
- **Instance Management**: Discovers existing client, launches if needed
- **Automated Setup**: Hostname configuration, DNS registration
- **Tool Installation**: Includes `scratch-dna` benchmark tool, monitoring utilities

**Usage:**
```bash
# Deploy client instance (auto-detects AMI)
./ec2-client.sh

# Use x86_64 instance type
EC2_TYPE="t3.medium" ./ec2-client.sh

# Use ARM64 instance type  
EC2_TYPE="a1.medium" ./ec2-client.sh

# Override with custom AMI
AMI_IMAGE="ami-custom123" ./ec2-client.sh
```

**Configuration (Environment Variables):**
- `INSTANCE_NAME="ceph-client"` - Client instance name
- `EC2_TYPE="c8gd.xlarge"` - Instance type (c8gd.xlarge/i3.large/a1.medium/t3a.small)
- `AMI_ARM="ami-03be04a3da3a40226"` - Rocky Linux 9 ARM64 AMI
- `AMI_X86="ami-0fadb4bc4d6071e9e"` - Rocky Linux 9 x86_64 AMI
- `AMI_IMAGE` - Override AMI (auto-detected from instance type if not set)
- `EC2_SECURITY_GROUPS="SSH-HTTP-ICMP ceph-cluster-sg ceph-client-sg"` - Security groups

**AMI Auto-Detection:**
Like the cluster script, automatically selects correct AMI based on instance architecture.

#### `ec2-client-cloud-init.txt`
**Client instance cloud-init configuration**

Handles client-specific package installation and configuration during instance boot.

**Installed Components:**
- **Ceph Tools**: `ceph-common`, `ceph-fuse` for CephFS access
- **Network Clients**: `nfs-utils`, `cifs-utils`, `s3cmd` for various protocols
- **Block Storage**: `iscsi-initiator-utils`, `nvme-cli` for iSCSI/NVMe-oF
- **Monitoring**: `htop`, `iotop`, `iftop`, `mc` for system monitoring
- **Benchmarking**: `scratch-dna` tool for storage performance testing

### 🔧 Infrastructure Support Scripts

#### `ec2-create-ceph-security-group.sh`
**AWS security group creation for Ceph clusters**

Creates and configures security groups with all necessary Ceph ports and protocols.

**Features:**
- Creates `ceph-cluster-sg` security group
- Configures ingress rules for Ceph services:
  - MON: 3300, 6789
  - MGR: 9283 (dashboard), 8765, 8443
  - OSD: 6800-7300
  - MDS: 6800
  - RGW: 7480, 8080
  - SSH: 22 (from security group itself for orchestration)

#### `ec2-create-ceph-client-security-group.sh`
**AWS security group creation for Ceph clients**

Creates dedicated security group for client instances with access to all Ceph protocols.

**Features:**
- Creates `ceph-client-sg` security group
- Configures ingress rules for client protocols:
  - **NFS**: 2049, 111 (TCP/UDP)
  - **SMB/CIFS**: 445, 139, 137, 138
  - **CephFS**: 3300, 6789, 6800-7300 (direct cluster access)
  - **S3/RadosGW**: 80, 443, 7480, 7481
  - **iSCSI**: 3260, 860-861
  - **NVMe-oF**: 4420-4430

**Usage:**
```bash
# Create client security group
./ec2-create-ceph-client-security-group.sh vpc-0123456789abcdef0
```

#### `ebs-create-attach.sh`
**EBS volume provisioning and attachment**

Creates and attaches EBS volumes to EC2 instances for Ceph storage.

**Usage:**
```bash
# Attach 6x 125GB ST1 volumes to instance
./ebs-create-attach.sh i-1234567890abcdef0 st1 125 6
```

**Parameters:**
1. Instance ID
2. Volume type (st1, gp3, io2)
3. Volume size (GB)
4. Number of volumes

#### `ebs-delete-unused.sh`
**EBS volume cleanup utility**

Identifies and deletes unattached EBS volumes to prevent cost accumulation.

**Features:**
- Lists all unattached volumes
- Provides deletion commands
- Safety checks to prevent accidental deletion of attached volumes

### 🔄 Utility Scripts

#### `remote-file-copy.sh`
**Cross-host file transfer and SSH key distribution**

Provides functions for secure file transfers between remote hosts using the local machine as a relay.

**Key Functions:**
- **`remote_file_copy()`** - Copy files between hosts preserving permissions
- **`remote_ssh_key_copy()`** - Distribute SSH keys to authorized_keys files

**Features:**
- Works through local machine (no direct host-to-host connections needed)
- Preserves file permissions and ownership
- Handles sudo access and protected directories
- Creates target directories automatically

**Usage:**
```bash
# Copy configuration file
remote_file_copy 'user@host1:/etc/ceph/ceph.conf' 'user@host2:/etc/ceph/ceph.conf'

# Copy SSH key
remote_ssh_key_copy 'user@host1:/etc/ceph/ceph.pub' 'user@host2' 'root'
```

#### `deploy-lambda.sh`
**AWS Lambda deployment automation**

Packages and deploys Lambda functions with proper IAM roles and permissions.

**Features:**
- Creates deployment packages
- Configures IAM roles and policies
- Handles Lambda function updates
- Sets up CloudWatch event triggers

## Configuration Files

### `ec2-cloud-init.txt`
Cloud-init configuration for EC2 instances. Handles:
- Package installation (podman, lvm2, etc.)
- System configuration
- Initial setup tasks

## Deployment Workflow

### Cluster Deployment
1. **Security Setup**: Run `ec2-create-ceph-security-group.sh`
2. **Cluster Launch**: Run `ec2-create-instances.sh [num_instances]`
3. **Automatic Process**:
   - Launches EC2 instances
   - Attaches EBS volumes
   - Bootstraps first node with Ceph
   - Adds additional nodes to cluster
   - Creates OSDs with optimal HDD/SSD ratios

### Client Deployment  
1. **Client Security**: Run `ec2-create-ceph-client-security-group.sh`
2. **Client Launch**: Run `ec2-client.sh`
3. **Access Configuration**: Configure client access to cluster via desired protocols

## Architecture

- **First Node**: Acts as cluster orchestrator (runs MON, MGR services)
- **Additional Nodes**: Join cluster and provide OSD services
- **Client Node**: Dedicated client instance with multi-protocol access
- **Storage**: ST1 volumes for cost-effective bulk storage
- **Network**: Private cluster communication + public management access

## Current Configuration

### Cluster Nodes
- **Instance Type**: i3.4xlarge (x86_64, NVMe SSD + network-optimized)
- **AMI**: Auto-detected based on architecture (ARM64: `ami-03be04a3da3a40226`, x86_64: `ami-0fadb4bc4d6071e9e`)
- **Storage**: 6x 125GB ST1 volumes per node + local NVMe
- **Ceph Version**: 19.2.2 (Squid - latest stable)

### Client Nodes  
- **Instance Type**: c8gd.xlarge (ARM64, cost-efficient with local NVMe)
- **AMI**: Auto-detected based on architecture
- **Protocols**: NFS, SMB/CIFS, CephFS, S3/RadosGW, iSCSI, NVMe-oF

## Monitoring & Maintenance

- **Cluster Status**: `sudo /usr/local/bin/cephadm shell -- ceph -s`
- **Device Status**: `sudo /usr/local/bin/cephadm shell -- ceph orch device ls`
- **OSD Status**: `sudo /usr/local/bin/cephadm shell -- ceph osd tree`
- **Clean Unused Volumes**: Run `ebs-delete-unused.sh` periodically

## Client Usage Examples

### CephFS Mount
```bash
# Direct mount using ceph-fuse
sudo ceph-fuse /mnt/cephfs -m <mon-host>:6789 --name client.admin

# Kernel client mount
sudo mount -t ceph <mon-host>:6789:/ /mnt/cephfs -o name=admin
```

### S3/RadosGW Access
```bash
# Configure s3cmd
s3cmd --configure

# List buckets
s3cmd ls

# Upload file
s3cmd put file.txt s3://mybucket/
```

### iSCSI Connection
```bash
# Discover targets
sudo iscsiadm -m discovery -t st -p <gateway-ip>

# Login to target
sudo iscsiadm -m node -T <target-name> -p <gateway-ip> --login

# List connected devices
lsblk
```

### NVMe-oF Connection
```bash
# Connect to NVMe target
sudo nvme connect -t tcp -a <gateway-ip> -s 4420 -n <nqn>

# List NVMe devices
sudo nvme list
```

### Performance Testing
```bash
# Run storage benchmark
scratch-dna /mnt/cephfs/testfile 1G
```

## CephFS File System Setup

### Overview
CephFS provides a POSIX-compliant distributed file system built on Ceph's object storage. This setup uses a **hybrid storage approach**:
- **Metadata Pool**: SSD-backed, replicated for high performance and reliability
- **Data Pool**: HDD-backed, erasure coded for efficient bulk storage

### Prerequisites
- Ceph cluster with mixed SSD/HDD storage deployed
- At least one SSD per host for metadata performance
- Minimum 3 hosts for erasure coding (k=2, m=1)

### Step 1: Create SSD Metadata Pool

Create a CRUSH rule and replicated pool for CephFS metadata using SSDs:

```bash
# Create CRUSH rule for SSD devices
ceph osd crush rule create-replicated ssd_rule default host ssd

# Create metadata pool (64 PGs for small-medium clusters)
ceph osd pool create cephfs_metadata_pool 64 64 replicated ssd_rule

# Configure replication (3 copies, minimum 2)
ceph osd pool set cephfs_metadata_pool size 3
ceph osd pool set cephfs_metadata_pool min_size 2

# Enable fast read for metadata performance
ceph osd pool set cephfs_metadata_pool fast_read true
```

### Step 2: Create HDD Data Pool with Erasure Coding

Create an erasure-coded pool for CephFS data using HDDs:

```bash
# Create erasure coding profile (k=2, m=2 = 2 data + 2 parity)
ceph osd erasure-code-profile set ec42_profile \
  k=2 m=2 \
  crush-failure-domain=host \
  crush-device-class=hdd \
  plugin=jerasure \
  technique=reed_sol_van

# Create CRUSH rule for erasure coded data pool
ceph osd crush rule create-erasure hdd_data_ec_rule ec42_profile

# Create data pool (128 PGs for larger data storage)
ceph osd pool create cephfs_data_pool 128 128 erasure ec42_profile

# Mark as bulk storage for optimization
ceph osd pool set cephfs_data_pool bulk true

# Enable compression for space efficiency (optional)
ceph osd pool set cephfs_data_pool compression_algorithm lz4
ceph osd pool set cephfs_data_pool compression_mode aggressive
```

### Step 3: Create CephFS File System

```bash
# Create the file system
ceph fs new myfs cephfs_metadata_pool cephfs_data_pool --force

# Enable MDS autoscaler (recommended)
ceph fs set myfs allow_standby_replay true
ceph fs set myfs max_mds 2

# Verify file system creation
ceph fs status myfs
```

### Step 4: Deploy MDS Daemons

```bash
# Deploy MDS daemons (one active, one standby per filesystem)
ceph orch apply mds myfs --placement="3"

# Check MDS status
ceph fs status
ceph mds stat
```

### Step 5: Client Access Setup

#### Prepare Client Authentication

Copy Ceph configuration and credentials from the admin container to client systems:

```bash
# On Ceph cluster node - extract files from cephadm container
sudo /usr/local/bin/cephadm shell -- cat /etc/ceph/ceph.conf > /tmp/ceph.conf
sudo /usr/local/bin/cephadm shell -- cat /etc/ceph/ceph.client.admin.keyring > /tmp/ceph.keyring

# Copy files to client system (replace CLIENT_IP with your client IP)
scp /tmp/ceph.conf root@CLIENT_IP:/etc/ceph/
scp /tmp/ceph.keyring root@CLIENT_IP:/etc/ceph/

# Or manually copy the contents to client /etc/ceph/ directory
```

#### Extract Secret Key

On the client system, extract the admin secret key:

```bash
# Create secret file from keyring
grep key /etc/ceph/ceph.keyring | cut -d' ' -f3 > /etc/ceph/secret

# Secure the secret file
chmod 600 /etc/ceph/secret
```

#### Mount CephFS

Mount the CephFS filesystem on the client:

```bash
# Create mount point
mkdir -p /mnt/cephfs

# Mount using kernel client (replace IPs with your MON addresses)
mount -t ceph 172.31.14.115,172.31.14.115,172.31.14.221,172.31.0.107:/ /mnt/cephfs \
  -o name=admin,secretfile=/etc/ceph/secret,mds_namespace=myfs

# Verify mount
df -h /mnt/cephfs
ls -la /mnt/cephfs
```

#### Alternative: ceph-fuse Mount

For environments where kernel client isn't available:

```bash
# Install ceph-fuse (already included in client cloud-init)
# sudo dnf install ceph-fuse

# Mount using FUSE
ceph-fuse /mnt/cephfs -m 172.31.14.115,172.31.14.115,172.31.14.221,172.31.0.107 \
  --name admin --keyring /etc/ceph/ceph.keyring \
  --client-fs myfs

# Verify mount
df -h /mnt/cephfs
```

#### Persistent Mounting

Add to `/etc/fstab` for automatic mounting:

```bash
# Kernel client mount in /etc/fstab
echo "172.31.14.115,172.31.14.115,172.31.14.221,172.31.0.107:/ /mnt/cephfs ceph name=admin,secretfile=/etc/ceph/secret,mds_namespace=myfs,_netdev 0 0" >> /etc/fstab

# Test fstab entry
umount /mnt/cephfs
mount -a
```

#### Client Configuration Options

Common mount options for performance and reliability:

```bash
# Performance-optimized mount
mount -t ceph MON_IPS:/ /mnt/cephfs \
  -o name=admin,secretfile=/etc/ceph/secret,mds_namespace=myfs,\
cache=strict,fsc,rsize=16777216,wsize=16777216

# High availability mount with multiple MONs
mount -t ceph 172.31.14.115:6789,172.31.14.221:6789,172.31.0.107:6789:/ /mnt/cephfs \
  -o name=admin,secretfile=/etc/ceph/secret,mds_namespace=myfs,\
recover_session=clean,_netdev
```

#### Mount Options Explained

- **`name=admin`**: Ceph client user name
- **`secretfile=/etc/ceph/secret`**: Path to secret key file
- **`mds_namespace=myfs`**: CephFS filesystem name
- **`cache=strict`**: Enable client-side caching
- **`fsc`**: Enable local file caching
- **`rsize/wsize=16777216`**: 16MB read/write buffer sizes
- **`recover_session=clean`**: Handle MDS failures gracefully
- **`_netdev`**: Wait for network before mounting (fstab)

#### Troubleshooting Client Mounts

```bash
# Check client connection status
ceph tell mds.myfs.hostname client ls

# View client performance
ceph daemon mds.myfs.hostname perf dump | grep client

# Debug mount issues
dmesg | grep ceph
journalctl -u ceph-fuse

# Test connectivity to MONs
telnet 172.31.14.115 6789
```

### Pool Configuration Details

#### Metadata Pool (SSD)
- **Type**: Replicated (3 copies)
- **Device Class**: SSD
- **PG Count**: 64 (adjust based on cluster size)
- **Use Case**: File/directory metadata, small files
- **Performance**: High IOPS, low latency

#### Data Pool (HDD) 
- **Type**: Erasure Coded (k=2, m=1)
- **Device Class**: HDD  
- **PG Count**: 128 (adjust based on data size)
- **Use Case**: Large file data blocks
- **Efficiency**: 50% overhead (vs 200% for replication)

### Erasure Code Profile Options

```bash
# View available profiles
ceph osd erasure-code-profile ls

# Create different profiles for various redundancy levels:

# k=4, m=2 (higher efficiency, requires 6+ hosts)
ceph osd erasure-code-profile set ec64_profile k=4 m=2 crush-failure-domain=host crush-device-class=hdd

# k=3, m=2 (balanced, requires 5+ hosts)  
ceph osd erasure-code-profile set ec53_profile k=3 m=2 crush-failure-domain=host crush-device-class=hdd
```

### Performance Tuning

```bash
# Optimize MDS cache size (per MDS daemon)
ceph config set mds mds_cache_memory_limit 4294967296  # 4GB

# Optimize client cache
ceph config set client client_cache_size 134217728     # 128MB

# Enable async I/O for better performance
ceph config set client client_oc_size 104857600       # 100MB
```

### Monitoring CephFS

```bash
# File system status
ceph fs status myfs

# MDS performance metrics
ceph daemon mds.myfs.hostname perf dump

# Pool usage
ceph df detail

# Client connections
ceph tell mds.myfs.hostname client ls
```

### Backup and Snapshots

```bash
# Enable snapshots on CephFS
ceph fs set myfs allow_new_snaps true

# Create directory snapshots (from mounted client)
mkdir /mnt/cephfs/mydir/.snap/snapshot_name

# List snapshots
ls /mnt/cephfs/mydir/.snap/
```

### Troubleshooting CephFS

#### Common Issues
- **Slow metadata operations**: Check MDS cache settings and SSD performance
- **Unbalanced data**: Verify CRUSH rules and device classes
- **MDS failures**: Check MDS logs and standby daemon availability

#### Debug Commands
```bash
# Check MDS health
ceph health detail | grep -i mds

# View MDS logs
ceph log last 50 | grep -i mds

# Verify pool CRUSH rules
ceph osd pool get cephfs_metadata_pool crush_rule
ceph osd pool get cephfs_data_pool crush_rule
```

## Troubleshooting

### Mount Ceph Container
```bash
sudo /usr/local/bin/cephadm shell
```

### Manual OSD Creation
If the Web UI has issues with AWS device detection:

```bash
# Single device
ceph orch daemon add osd ceph-test-1:/dev/nvme2n1

# All available devices
ceph orch daemon add osd <hostname> --all-available-devices
```

### Device Detection Issues
The toolkit includes intelligent device detection that handles:
- **Timing Issues**: Newly added nodes need time for orchestrator inventory
- **Rejected Devices**: Devices with partitions, wrong size, or hardware issues
- **In-Use Devices**: Already configured devices (normal condition)

Check device status with detailed analysis:
```bash
ceph orch device ls --format json
```

## Security Features

- **Network Isolation**: Security groups restrict access to necessary ports only
- **SSH Key Management**: Automated distribution of Ceph orchestrator keys
- **Least Privilege**: IAM roles with minimal required permissions
- **Encrypted Storage**: EBS volumes support encryption at rest

## Cost Optimization

- **ST1 Volumes**: Throughput-optimized for bulk storage workloads
- **Instance Right-sizing**: c8gd.large provides optimal CPU/memory/network balance
- **Volume Cleanup**: Automated detection and cleanup of unused EBS volumes
- **Spot Instance Support**: Can be configured for non-production workloads