# Phase 3: Container Development, Fluent Bit Setup, and EKS Preparation

## Overview
This phase covers developing the containerized applications, setting up Fluent Bit for log collection, and preparing all Kubernetes manifests. All containers are built for ARM64 architecture to run on AWS Graviton instances. The code will be pushed to GitHub and built by Jenkins on EC2.

**Key Components:**
- Discovery Service (Go 1.24) - Discovers Aurora instances and publishes to Kafka
  - Reads from DynamoDB tracking table to check for new logs
  - Writes instance/cluster metadata to instance-registry table
  - Uses Valkey cache to reduce RDS API calls by 70-90%
- Processor Service (Go 1.24) - Processes logs from Kafka and stores in S3
  - Creates job entries in jobs table when starting processing
  - Updates tracking table with processing state (position, size)
  - Updates job status (completed/failed) in jobs table
  - Sends parsed logs to OpenObserve for querying
- Kafka 4.0 (KRaft mode) - Message broker without ZooKeeper dependency
- OpenObserve - Log aggregation with 90-day retention
- Fluent Bit - Kubernetes log collection to separate S3 bucket


# codebase
https://github.com/mahityagi14/aurora-logs.git


# Jenkins CI/CD Setup on EC2 for ARM64 Container Builds

## Overview
This guide covers setting up Jenkins on AWS EC2 Ubuntu 24.04 to build ARM64 container images from GitHub repository and push them to Amazon ECR. This setup bridges the gap between code development and EKS deployment.

**Key Requirements:**
- Jenkins on EC2 Ubuntu 24.04
- GitHub repository: `https://github.com/anshtyagi14/aurora-log-system.git`
- ARM64 image builds exclusively
- Push to ECR repository created in Phase 2
- Integration with EKS deployment from Phase 4

## Prerequisites
- jenkins insatlled on ubuntu os

## Step 1: Install Jenkins on Ubuntu 24.04

### 1.1 Update System and Install Java
```bash
# Update system
sudo apt update && sudo apt upgrade -y

# Install Java 17 (required for Jenkins)
sudo apt install fontconfig openjdk-21-jre

# Verify Java installation
java -version
```

### 1.2 Install Jenkins
```bash
sudo wget -O /etc/apt/keyrings/jenkins-keyring.asc \
  https://pkg.jenkins.io/debian/jenkins.io-2023.key
echo "deb [signed-by=/etc/apt/keyrings/jenkins-keyring.asc]" \
  https://pkg.jenkins.io/debian binary/ | sudo tee \
  /etc/apt/sources.list.d/jenkins.list > /dev/null
sudo apt-get update
sudo apt-get install jenkins
```

### 1.4 Get Initial Admin Password
```bash
sudo cat /var/lib/jenkins/secrets/initialAdminPassword
```

## Step 2: Install Docker and Configure for ARM64 Builds

### 2.1 Install Docker
```bash
# Install dependencies
sudo apt install -y apt-transport-https ca-certificates curl software-properties-common

# Add Docker GPG key
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg

# Add Docker repository
echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

# Install Docker
sudo apt update
sudo apt install -y docker-ce docker-ce-cli containerd.io

# Add jenkins user to docker group
sudo usermod -aG docker jenkins

# Restart Jenkins to apply group changes
sudo systemctl restart jenkins
```

### 2.2 Install Docker Buildx for Multi-Architecture Builds
```bash
# Install QEMU for cross-platform builds
sudo apt install -y qemu-user-static

# Create buildx builder for multi-arch
sudo -u jenkins docker buildx create --name arm64-builder --use
sudo -u jenkins docker buildx inspect --bootstrap

# Verify ARM64 support
sudo -u jenkins docker buildx ls
```

cd /tmp
wget https://go.dev/dl/go1.23.4.linux-amd64.tar.gz
sudo tar -C /usr/local -xzf go1.23.4.linux-amd64.tar.gz
rm go1.23.4.linux-amd64.tar.gz

# Add to system PATH
echo 'export PATH=$PATH:/usr/local/go/bin' | sudo tee -a /etc/profile
echo 'export PATH=$PATH:/usr/local/go/bin' | sudo tee -a /var/lib/jenkins/.bashrc

# Verify installation
/usr/local/go/bin/go version

# Install build tools
sudo apt-get update
sudo apt-get install -y build-essential gcc

## Step 4: Configure Jenkins

### 4.2 Install Required Plugins
Navigate to **Manage Jenkins** → **Manage Plugins** → **Available plugins**

**Note**: Many core plugins are pre-installed. Install these additional plugins if not already present:

**Essential Plugins:**
- **GitHub** (GitHub plugin for integration)
- **Docker Pipeline** (for Docker commands in pipeline)
- **AWS Steps** (for AWS CLI commands)
- **AnsiColor** (for colored console output)

To check installed plugins:
1. Go to **Manage Jenkins** → **Manage Plugins** → **Installed plugins**
2. Search for the above plugins
3. If any core plugins are missing, they can be found under different names:
   - "Pipeline" might be listed as "Pipeline: API" or "Pipeline: Groovy"
   - "Credentials Binding" is part of "Credentials Plugin"

### 4.3 Configure GitHub Credentials
1. Go to **Manage Jenkins** → **Manage Credentials**
2. Click **System** → **Global credentials** → **Add Credentials**
3. Configure:
   - Kind: **Username with password**
   - Username: `your-github-username`
   - Password: `your-github-personal-access-token`
   - ID: `github-credentials`
   - Description: `GitHub PAT for aurora-log-system`

## Step 5: Create Jenkins Pipeline Job

### 5.1 Create New Pipeline Job
1. Click **New Item**
2. Enter name: `aurora-log-system-build`
3. Select **Pipeline**
4. Click **OK**

### 5.2 Configure Pipeline
in the codebase

## Step 7: Test the Pipeline

### 7.1 Manual Build Test
1. In Jenkins, go to your pipeline job
2. Click **Build Now**
3. Monitor the build in **Console Output**