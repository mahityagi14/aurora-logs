# Kubernetes Authentication Issue

## Problem
The jenkins-ecr-user (arn:aws:iam::072006186126:user/jenkins-ecr-user) cannot authenticate to the EKS cluster even though it has administrator access.

## Root Cause
The IAM user needs to be added to the aws-auth ConfigMap in the kube-system namespace of the EKS cluster. Only the cluster creator or users explicitly added to aws-auth can access the cluster.

## Solution
The cluster administrator needs to:

1. Access the cluster with the creator's credentials
2. Edit the aws-auth ConfigMap:
   ```bash
   kubectl edit configmap aws-auth -n kube-system
   ```

3. Add the jenkins-ecr-user to the mapUsers section:
   ```yaml
   mapUsers: |
     - userarn: arn:aws:iam::072006186126:user/jenkins-ecr-user
       username: jenkins-ecr-user
       groups:
         - system:masters
   ```

## Alternative Solutions

1. Use the IAM role that created the cluster
2. Use eksctl or AWS CLI with the cluster creator's credentials to add the user:
   ```bash
   eksctl create iamidentitymapping \
     --cluster aurora-logs-poc-cluster \
     --arn arn:aws:iam::072006186126:user/jenkins-ecr-user \
     --username jenkins-ecr-user \
     --group system:masters
   ```

3. Create the namespace manually after fixing authentication and then import it to Terraform

## Current Status
- All infrastructure is created except the Kubernetes namespace
- The namespace creation fails with "Unauthorized" error
- kubectl and aws-iam-authenticator are properly installed