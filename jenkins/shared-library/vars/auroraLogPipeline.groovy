def call(Map config = [:]) {
    // Default configuration
    def defaultConfig = [
        awsRegion: 'us-east-1',
        goVersion: '1.24',
        dockerRegistry: '',
        kubernetesNamespace: 'aurora-logs',
        runTests: true,
        runSecurityScan: true,
        deployToK8s: false,
        notificationChannel: '#aurora-logs-ci'
    ]
    
    // Merge configurations
    def pipelineConfig = defaultConfig + config
    
    pipeline {
        agent any
        
        environment {
            AWS_REGION = "${pipelineConfig.awsRegion}"
            ECR_REGISTRY = "${pipelineConfig.dockerRegistry}"
            K8S_NAMESPACE = "${pipelineConfig.kubernetesNamespace}"
            GO_VERSION = "${pipelineConfig.goVersion}"
        }
        
        stages {
            stage('Initialize') {
                steps {
                    script {
                        // Set build information
                        env.GIT_COMMIT_SHORT = sh(returnStdout: true, script: 'git rev-parse --short HEAD').trim()
                        env.BUILD_VERSION = "${env.BUILD_NUMBER}-${env.GIT_COMMIT_SHORT}"
                        
                        // Print configuration
                        echo "Pipeline Configuration:"
                        echo "AWS Region: ${pipelineConfig.awsRegion}"
                        echo "Docker Registry: ${pipelineConfig.dockerRegistry}"
                        echo "Build Version: ${env.BUILD_VERSION}"
                    }
                }
            }
            
            stage('Quality Gates') {
                when {
                    expression { pipelineConfig.runTests }
                }
                parallel {
                    stage('Lint') {
                        steps {
                            auroraLint()
                        }
                    }
                    
                    stage('Test') {
                        steps {
                            auroraTest()
                        }
                    }
                    
                    stage('Security') {
                        when {
                            expression { pipelineConfig.runSecurityScan }
                        }
                        steps {
                            auroraSecurityScan()
                        }
                    }
                }
            }
            
            stage('Build') {
                steps {
                    auroraBuild(version: env.BUILD_VERSION)
                }
            }
            
            stage('Package') {
                steps {
                    auroraDockerBuild(
                        registry: pipelineConfig.dockerRegistry,
                        tag: env.BUILD_VERSION
                    )
                }
            }
            
            stage('Publish') {
                when {
                    anyOf {
                        branch 'main'
                        branch 'develop'
                    }
                }
                steps {
                    auroraDockerPush(
                        registry: pipelineConfig.dockerRegistry,
                        tag: env.BUILD_VERSION
                    )
                }
            }
            
            stage('Deploy') {
                when {
                    allOf {
                        branch 'main'
                        expression { pipelineConfig.deployToK8s }
                    }
                }
                steps {
                    auroraDeploy(
                        namespace: pipelineConfig.kubernetesNamespace,
                        version: env.BUILD_VERSION
                    )
                }
            }
        }
        
        post {
            always {
                auroraCleanup()
            }
            
            success {
                auroraNotify(
                    status: 'SUCCESS',
                    channel: pipelineConfig.notificationChannel,
                    version: env.BUILD_VERSION
                )
            }
            
            failure {
                auroraNotify(
                    status: 'FAILURE',
                    channel: pipelineConfig.notificationChannel,
                    version: env.BUILD_VERSION
                )
            }
        }
    }
}