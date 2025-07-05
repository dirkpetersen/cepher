
These scripts are deploying a Ceph Cluster in AWS for Testing 

- the bootstraping is driven by cephadm using podman, documentation: 
   https://docs.ceph.com/en/latest/cephadm/install/#bootstrap-a-new-cluster
- all nodes are OSD by default but the the first node is also a mon node as it is bootstrapped 
- the number $HDDS_PER_SSD (default 6) defines how many HDD (data) will be defined
  per SSD which will carry the bluestore databases 
- ALL ceph logic should be in bootstrap-node.sh and not in ec2-create-instances.sh should not 
- it should just upload the bootstrap-node.sh script to each node and execute it
- use the cephadm/orchestrator framework introduced in Octopus (v15+) over legacy methods
- Use modern bash, for example use [[ ]] for control structures instead [  ] and encapsulate vars with curly braces


