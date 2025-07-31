@Library('aurora-log-pipeline') _

// Configuration based on branch
def getConfig() {
    switch(env.BRANCH_NAME) {
        case 'main':
            return [
                awsRegion: 'us-east-1',
                dockerRegistry: "${AWS_ACCOUNT_ID}.dkr.ecr.us-east-1.amazonaws.com",
                kubernetesNamespace: 'aurora-logs-prod',
                deployToK8s: true,
                runSecurityScan: true,
                notificationChannel: '#aurora-logs-prod'
            ]
        case 'develop':
            return [
                awsRegion: 'us-east-1',
                dockerRegistry: "${AWS_ACCOUNT_ID}.dkr.ecr.us-east-1.amazonaws.com",
                kubernetesNamespace: 'aurora-logs-dev',
                deployToK8s: true,
                runSecurityScan: true,
                notificationChannel: '#aurora-logs-dev'
            ]
        case ~/^feature\/.*/:
            return [
                awsRegion: 'us-east-1',
                dockerRegistry: "${AWS_ACCOUNT_ID}.dkr.ecr.us-east-1.amazonaws.com",
                deployToK8s: false,
                runSecurityScan: false,
                notificationChannel: '#aurora-logs-dev'
            ]
        default:
            return [
                deployToK8s: false,
                runSecurityScan: false
            ]
    }
}

// Execute pipeline with branch-specific configuration
auroraLogPipeline(getConfig())