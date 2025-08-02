def call(Map args = [:]) {
    def coverage = args.coverage ?: true
    def race = args.race ?: true
    
    sh """
        # Run tests for each module
        for module in discovery processor common; do
            echo "🧪 Testing \$module..."
            cd \$module
            
            # Download dependencies
            go mod download
            
            # Run tests with options
            TEST_ARGS="-v"
            if [ "${race}" = "true" ]; then
                TEST_ARGS="\$TEST_ARGS -race"
            fi
            if [ "${coverage}" = "true" ]; then
                TEST_ARGS="\$TEST_ARGS -coverprofile=coverage.out -covermode=atomic"
            fi
            
            go test \$TEST_ARGS ./...
            
            # Generate coverage report
            if [ "${coverage}" = "true" ] && [ -f coverage.out ]; then
                go tool cover -func=coverage.out
                go tool cover -html=coverage.out -o coverage.html
            fi
            
            cd ..
        done
    """
    
    // Publish test results if available
    if (coverage) {
        publishHTML([
            allowMissing: false,
            alwaysLinkToLastBuild: true,
            keepAll: true,
            reportDir: '.',
            reportFiles: '**/coverage.html',
            reportName: 'Test Coverage Report'
        ])
    }
}