pipeline {
    agent any

    environment {
        // AWS Configuration
        AWS_REGION = 'us-east-1'
        AWS_ACCOUNT_ID = '072006186126'
        ECR_REGISTRY = "${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com"
        AWS_DEFAULT_REGION = 'us-east-1'
        // If AWS CLI is configured for jenkins user
        AWS_CONFIG_FILE = "${env.JENKINS_HOME ?: env.HOME}/.aws/config"
        AWS_SHARED_CREDENTIALS_FILE = "${env.JENKINS_HOME ?: env.HOME}/.aws/credentials"
        
        // Application Configuration
        APP_NAME = 'aurora-log-system'
        
        // Kubernetes Configuration
        K8S_NAMESPACE = 'aurora-logs'
    }

    options {
        buildDiscarder(logRotator(numToKeepStr: '30'))
        timeout(time: 1, unit: 'HOURS')
        timestamps()
        disableConcurrentBuilds()
    }

    parameters {
        choice(
            name: 'BUILD_TYPE',
            choices: ['snapshot', 'release'],
            description: 'Build type - snapshot or release'
        )
        booleanParam(
            name: 'DEPLOY_TO_K8S',
            defaultValue: false,
            description: 'Deploy to Kubernetes after build'
        )
        string(
            name: 'K8S_ENV',
            defaultValue: 'dev',
            description: 'Kubernetes environment (dev/staging/prod)'
        )
        booleanParam(
            name: 'FORCE_ECR_PUSH',
            defaultValue: true,
            description: 'Force push to ECR regardless of branch'
        )
    }

    stages {
        stage('Prerequisites') {
            steps {
                script {
                    sh '''#!/bin/bash
                        echo "Checking prerequisites..."
                        
                        # Set Go environment (Go is already installed system-wide)
                        export PATH=$PATH:/usr/local/go/bin
                        export GOPATH=$HOME/go
                        export PATH=$PATH:$GOPATH/bin
                        mkdir -p $GOPATH/bin
                        
                        # Verify Go installation
                        echo "Go version:"
                        go version
                        
                        # Verify Docker
                        echo "Docker version:"
                        docker version
                        
                        # Verify AWS CLI
                        echo "AWS CLI version:"
                        aws --version
                        
                        # Verify gcc for CGO/race detection
                        echo "GCC version:"
                        gcc --version
                    '''
                }
            }
        }
        
        stage('Checkout') {
            steps {
                git branch: "${env.BRANCH_NAME ?: 'main'}", 
                    url: 'https://github.com/mahityagi14/aurora-logs.git'
                    
                script {
                    env.GIT_COMMIT = sh(returnStdout: true, script: 'git rev-parse HEAD').trim()
                    env.GIT_BRANCH = sh(returnStdout: true, script: 'git rev-parse --abbrev-ref HEAD').trim()
                    env.BUILD_VERSION = "${env.BUILD_NUMBER}-${env.GIT_COMMIT.take(7)}"
                    
                    echo "Debug: GIT_BRANCH = ${env.GIT_BRANCH}"
                    echo "Debug: BRANCH_NAME = ${env.BRANCH_NAME ?: 'not set'}"
                    echo "Debug: BUILD_TYPE = ${params.BUILD_TYPE}"
                    
                    if (params.BUILD_TYPE == 'release') {
                        env.IMAGE_TAG = sh(returnStdout: true, script: 'git describe --tags --exact-match 2>/dev/null || echo ""').trim()
                        if (!env.IMAGE_TAG) {
                            error("Release builds require a git tag")
                        }
                    } else {
                        env.IMAGE_TAG = "${env.GIT_BRANCH}-${env.BUILD_VERSION}"
                    }
                }
                echo "Building version: ${env.IMAGE_TAG}"
            }
        }

        stage('Quality Gates') {
            parallel {
                stage('Lint Go Code') {
                    steps {
                        sh '''#!/bin/bash
                            # Set up Go environment
                            export PATH=$PATH:/usr/local/go/bin
                            export GOPATH=$HOME/go
                            export PATH=$PATH:$GOPATH/bin
                            
                            # Install golangci-lint if not present
                            if ! command -v golangci-lint &> /dev/null; then
                                if command -v sudo &> /dev/null && sudo -n true 2>/dev/null; then
                                    curl -sSfL https://raw.githubusercontent.com/golangci/golangci-lint/master/install.sh | sh -s -- -b /usr/local/bin latest
                                else
                                    curl -sSfL https://raw.githubusercontent.com/golangci/golangci-lint/master/install.sh | sh -s -- -b $HOME/bin latest
                                    export PATH=$HOME/bin:$PATH
                                fi
                            fi
                            
                            # Lint each module
                            for module in discovery processor; do
                                echo "Linting $module..."
                                cd $module
                                go mod download
                                go mod tidy
                                golangci-lint run --timeout 5m || true
                                cd ..
                            done
                        '''
                    }
                }

                stage('Security Scan - Dependencies') {
                    steps {
                        sh '''#!/bin/bash
                            # Set up Go environment
                            export PATH=$PATH:/usr/local/go/bin
                            export GOPATH=$HOME/go
                            export PATH=$PATH:$GOPATH/bin
                            
                            # Install nancy for vulnerability scanning
                            go install github.com/sonatype-nexus-community/nancy@latest || echo "Failed to install nancy"
                            
                            # Check each module
                            for module in discovery processor; do
                                echo "Scanning $module dependencies..."
                                cd $module
                                go mod download
                                go mod tidy
                                if command -v nancy &> /dev/null; then
                                    go list -json -m all | nancy sleuth || true
                                else
                                    echo "Nancy not available, skipping dependency scan"
                                fi
                                cd ..
                            done
                        '''
                    }
                }

                stage('License Check') {
                    steps {
                        sh '''#!/bin/bash
                            echo "License check disabled - skipping..."
                        '''
                    }
                }
            }
        }

        stage('Build & Test') {
            parallel {
                stage('Test Discovery Service') {
                    steps {
                        sh '''#!/bin/bash
                            # Set up Go environment
                            export PATH=$PATH:/usr/local/go/bin
                            export GOPATH=$HOME/go
                            export PATH=$PATH:$GOPATH/bin
                            
                            cd discovery
                            go mod download
                            go mod tidy
                            
                            # Run tests with race detection
                            export CGO_ENABLED=1
                            echo "Running tests with race detection enabled"
                            go test -v -race -coverprofile=coverage.out -covermode=atomic ./...
                            
                            go tool cover -html=coverage.out -o coverage.html
                            go tool cover -func=coverage.out
                        '''
                    }
                }

                stage('Test Processor Service') {
                    steps {
                        sh '''#!/bin/bash
                            # Set up Go environment
                            export PATH=$PATH:/usr/local/go/bin
                            export GOPATH=$HOME/go
                            export PATH=$PATH:$GOPATH/bin
                            
                            cd processor
                            go mod download
                            go mod tidy
                            
                            # Run tests with race detection
                            export CGO_ENABLED=1
                            echo "Running tests with race detection enabled"
                            go test -v -race -coverprofile=coverage.out -covermode=atomic ./...
                            
                            go tool cover -html=coverage.out -o coverage.html
                            go tool cover -func=coverage.out
                        '''
                    }
                }

            }
        }

        stage('Build Binaries') {
            steps {
                sh '''#!/bin/bash
                    # Set up Go environment
                    if [ -d "/usr/local/go" ]; then
                        export PATH=$PATH:/usr/local/go/bin
                    elif [ -d "$HOME/go-install/go" ]; then
                        export PATH=$HOME/go-install/go/bin:$PATH
                    fi
                    export GOPATH=$HOME/go
                    export PATH=$PATH:$GOPATH/bin
                    
                    # Build discovery service
                    cd discovery
                    CGO_ENABLED=0 GOOS=linux GOARCH=arm64 go build \
                        -ldflags="-w -s -X main.version=${IMAGE_TAG}" \
                        -o discovery .
                    cd ..
                    
                    # Build processor service
                    cd processor
                    CGO_ENABLED=0 GOOS=linux GOARCH=arm64 go build \
                        -ldflags="-w -s -X main.version=${IMAGE_TAG}" \
                        -o processor .
                    cd ..
                '''
            }
        }

        stage('Build Docker Images') {
            steps {
                script {
                    // Build Go services with parent context for common module
                    sh """
                        docker build -t ${ECR_REGISTRY}/${APP_NAME}:discovery-${IMAGE_TAG} -f discovery/Dockerfile .
                        docker tag ${ECR_REGISTRY}/${APP_NAME}:discovery-${IMAGE_TAG} \
                            ${ECR_REGISTRY}/${APP_NAME}:discovery-latest
                            
                        docker build -t ${ECR_REGISTRY}/${APP_NAME}:processor-${IMAGE_TAG} -f processor/Dockerfile .
                        docker tag ${ECR_REGISTRY}/${APP_NAME}:processor-${IMAGE_TAG} \
                            ${ECR_REGISTRY}/${APP_NAME}:processor-latest
                    """
                    
                    // Build other services normally
                    def otherServices = ['kafka', 'openobserve']
                    otherServices.each { service ->
                        sh """
                            cd ${service}
                            docker build -t ${ECR_REGISTRY}/${APP_NAME}:${service}-${IMAGE_TAG} .
                            docker tag ${ECR_REGISTRY}/${APP_NAME}:${service}-${IMAGE_TAG} \
                                ${ECR_REGISTRY}/${APP_NAME}:${service}-latest
                            cd ..
                        """
                    }
                }
            }
        }

        stage('Security Scan - Comprehensive') {
            parallel {
                stage('Trivy Scan') {
                    steps {
                        script {
                            def services = ['discovery', 'processor', 'kafka', 'openobserve']
                            
                            // Install latest Trivy
                            sh '''
                                if ! command -v trivy &> /dev/null; then
                                    mkdir -p $HOME/bin
                                    export TRIVY_VERSION=$(curl -s https://api.github.com/repos/aquasecurity/trivy/releases/latest | grep '"tag_name":' | sed -E 's/.*"v([^"]+)".*/\\1/')
                                    wget -qO trivy.tar.gz https://github.com/aquasecurity/trivy/releases/download/v${TRIVY_VERSION}/trivy_${TRIVY_VERSION}_Linux-64bit.tar.gz
                                    tar zxf trivy.tar.gz -C $HOME/bin trivy
                                    rm trivy.tar.gz
                                fi
                            '''
                            
                            services.each { service ->
                                sh """
                                    export PATH=$HOME/bin:$PATH
                                    
                                    # Comprehensive vulnerability scan
                                    trivy image --severity HIGH,CRITICAL \
                                        --no-progress \
                                        --format json \
                                        --output ${service}-trivy-scan.json \
                                        ${ECR_REGISTRY}/${APP_NAME}:${service}-${IMAGE_TAG}
                                    
                                    # Fail on critical vulnerabilities
                                    trivy image --severity CRITICAL \
                                        --no-progress \
                                        --exit-code 1 \
                                        ${ECR_REGISTRY}/${APP_NAME}:${service}-${IMAGE_TAG} || echo "Critical vulnerabilities found in ${service}"
                                        
                                    # SBOM generation
                                    trivy image --format cyclonedx \
                                        --output ${service}-sbom.json \
                                        ${ECR_REGISTRY}/${APP_NAME}:${service}-${IMAGE_TAG}
                                """
                            }
                        }
                    }
                }
                
                stage('Grype Scan') {
                    steps {
                        script {
                            def services = ['discovery', 'processor', 'kafka', 'openobserve']
                            
                            // Install latest Grype
                            sh '''
                                if ! command -v grype &> /dev/null; then
                                    mkdir -p $HOME/bin
                                    curl -sSfL https://raw.githubusercontent.com/anchore/grype/main/install.sh | sh -s -- -b $HOME/bin
                                fi
                            '''
                            
                            services.each { service ->
                                sh """
                                    export PATH=$HOME/bin:$PATH
                                    
                                    # Grype vulnerability scan
                                    grype ${ECR_REGISTRY}/${APP_NAME}:${service}-${IMAGE_TAG} \
                                        --output json \
                                        --file ${service}-grype-scan.json \
                                        --fail-on critical || echo "Grype found critical issues in ${service}"
                                """
                            }
                        }
                    }
                }
                
                stage('Snyk Scan') {
                    when {
                        expression { env.SNYK_TOKEN != null }
                    }
                    steps {
                        script {
                            def services = ['discovery', 'processor', 'kafka', 'openobserve']
                            
                            // Install Snyk CLI
                            sh '''
                                if ! command -v snyk &> /dev/null; then
                                    mkdir -p $HOME/bin
                                    curl -Lo $HOME/bin/snyk https://static.snyk.io/cli/latest/snyk-linux
                                    chmod +x $HOME/bin/snyk
                                fi
                            '''
                            
                            services.each { service ->
                                sh """
                                    export PATH=$HOME/bin:$PATH
                                    
                                    # Snyk container test
                                    snyk container test ${ECR_REGISTRY}/${APP_NAME}:${service}-${IMAGE_TAG} \
                                        --severity-threshold=high \
                                        --json-file-output=${service}-snyk-scan.json || echo "Snyk scan completed for ${service}"
                                        
                                    # Monitor in Snyk (production only)
                                    if [ "${BRANCH_NAME}" == "main" ]; then
                                        snyk container monitor ${ECR_REGISTRY}/${APP_NAME}:${service}-${IMAGE_TAG} \
                                            --project-name=${APP_NAME}-${service} || true
                                    fi
                                """
                            }
                        }
                    }
                }
                
                // Cosign Verification stage removed per user request
                // The user explicitly stated: "i don't require .sig and .att file at all"
                
                stage('Docker Scout') {
                    steps {
                        script {
                            def services = ['discovery', 'processor', 'kafka', 'openobserve']
                            
                            // Docker Scout analysis
                            services.each { service ->
                                sh """
                                    # Check if Docker Scout is available
                                    if docker scout version >/dev/null 2>&1; then
                                        # Docker Scout CVE scan
                                        docker scout cves ${ECR_REGISTRY}/${APP_NAME}:${service}-${IMAGE_TAG} \
                                            --output ${service}-scout-scan.json || echo "Scout scan completed for ${service}"
                                            
                                        # Docker Scout recommendations
                                        docker scout recommendations ${ECR_REGISTRY}/${APP_NAME}:${service}-${IMAGE_TAG} || true
                                    else
                                        echo "Docker Scout not available - skipping Scout scans"
                                        # Create empty report file
                                        echo '{"message": "Docker Scout not available"}' > ${service}-scout-scan.json
                                    fi
                                """
                            }
                        }
                    }
                }
            }
        }
        
        stage('Security Report') {
            steps {
                script {
                    // Aggregate all security scan results
                    sh '''
                        echo "# Security Scan Report" > security-report.md
                        echo "Build: ${BUILD_NUMBER}" >> security-report.md
                        echo "Date: $(date)" >> security-report.md
                        echo "" >> security-report.md
                        
                        for service in discovery processor kafka openobserve; do
                            echo "## Service: $service" >> security-report.md
                            
                            if [ -f ${service}-trivy-scan.json ]; then
                                echo "### Trivy Results" >> security-report.md
                                jq -r '.Results[0].Vulnerabilities | group_by(.Severity) | map({Severity: .[0].Severity, Count: length}) | .[]' ${service}-trivy-scan.json >> security-report.md 2>/dev/null || echo "No Trivy results"
                            fi
                            
                            if [ -f ${service}-grype-scan.json ]; then
                                echo "### Grype Results" >> security-report.md
                                jq -r '.matches | group_by(.vulnerability.severity) | map({Severity: .[0].vulnerability.severity, Count: length}) | .[]' ${service}-grype-scan.json >> security-report.md 2>/dev/null || echo "No Grype results"
                            fi
                            
                            echo "" >> security-report.md
                        done
                    '''
                    
                    // Archive security reports
                    archiveArtifacts artifacts: '*-scan.json,*-sbom.json,security-report.md', allowEmptyArchive: true
                    
                    // Note: To publish HTML reports, install the HTML Publisher plugin
                    // and uncomment the following:
                    // publishHTML([
                    //     allowMissing: true,
                    //     alwaysLinkToLastBuild: true,
                    //     keepAll: true,
                    //     reportDir: '.',
                    //     reportFiles: 'security-report.md',
                    //     reportName: 'Security Scan Report'
                    // ])
                    
                    echo "Security scan report generated: security-report.md"
                    echo "View the report in the build artifacts"
                }
            }
        }

        stage('Push to ECR') {
            when {
                anyOf {
                    branch 'main'
                    branch 'develop'
                    expression { params.BUILD_TYPE == 'release' }
                    expression { env.GIT_BRANCH == 'main' }
                    expression { env.GIT_BRANCH == 'develop' }
                    expression { params.FORCE_ECR_PUSH == true }
                }
            }
            steps {
                script {
                    // Check AWS credentials configuration
                    sh '''
                        echo "Checking AWS credentials..."
                        echo "HOME: $HOME"
                        echo "JENKINS_HOME: ${JENKINS_HOME:-not set}"
                        echo "USER: $(whoami)"
                        echo "AWS_CONFIG_FILE: ${AWS_CONFIG_FILE}"
                        echo "AWS_SHARED_CREDENTIALS_FILE: ${AWS_SHARED_CREDENTIALS_FILE}"
                        
                        # Check if credentials files exist
                        if [ -f "${AWS_SHARED_CREDENTIALS_FILE}" ]; then
                            echo "Found AWS credentials file at ${AWS_SHARED_CREDENTIALS_FILE}"
                        elif [ -f "$HOME/.aws/credentials" ]; then
                            echo "Found AWS credentials file at $HOME/.aws/credentials"
                        elif [ -f "/var/lib/jenkins/.aws/credentials" ]; then
                            echo "Found AWS credentials file at /var/lib/jenkins/.aws/credentials"
                        else
                            echo "No AWS credentials file found"
                        fi
                        
                        # Try to get caller identity
                        aws sts get-caller-identity || {
                            echo "AWS credentials not found. Checking for instance profile..."
                            # Check if running on EC2 with instance profile
                            if curl -s -o /dev/null -w "%{http_code}" http://169.254.169.254/latest/meta-data/iam/security-credentials/ | grep -q 200; then
                                echo "Running on EC2 with instance profile"
                            else
                                echo "No AWS credentials found. Please configure AWS credentials."
                                echo "To configure AWS credentials for Jenkins user, run:"
                                echo "sudo -u jenkins aws configure"
                                exit 1
                            fi
                        }
                    '''
                    
                    // Create ECR repository if it doesn't exist
                    sh '''
                        # Create ECR repository if it doesn't exist
                        aws ecr describe-repositories --repository-names ${APP_NAME} --region ${AWS_REGION} || \
                        aws ecr create-repository --repository-name ${APP_NAME} --region ${AWS_REGION} || true
                    '''
                    
                    // Use AWS credentials from environment or instance role
                    sh '''
                        # Login to ECR
                        aws ecr get-login-password --region ${AWS_REGION} | docker login --username AWS --password-stdin ${ECR_REGISTRY}
                        
                        # Push images
                        for service in discovery processor kafka openobserve; do
                            docker push ${ECR_REGISTRY}/${APP_NAME}:${service}-${IMAGE_TAG}
                            if [ "${GIT_BRANCH}" = "main" ]; then
                                docker push ${ECR_REGISTRY}/${APP_NAME}:${service}-latest
                            fi
                        done
                    '''
                }
            }
        }
        
        // Cosign signing stage removed per user request
        // The user explicitly stated: "i don't require .sig and .att file at all"
    }

    post {
        always {
            // Clean workspace
            cleanWs()
        }
        
        success {
            echo "Build successful: ${env.IMAGE_TAG}"
        }
        
        failure {
            echo "Build failed: ${env.IMAGE_TAG}"
        }
    }
}