#!/bin/bash
set -o xtrace

# Configure EKS node
/etc/eks/bootstrap.sh ${cluster_name} \
  --b64-cluster-ca ${cluster_ca} \
  --apiserver-endpoint ${cluster_endpoint}

# Install SSM agent if enabled
%{ if enable_ssm ~}
yum install -y amazon-ssm-agent
systemctl enable amazon-ssm-agent
systemctl start amazon-ssm-agent
%{ endif ~}

# Additional user data
${additional_userdata}