def call() {
    sh '''
        # Install golangci-lint if not present
        if ! command -v golangci-lint &> /dev/null; then
            curl -sSfL https://raw.githubusercontent.com/golangci/golangci-lint/master/install.sh | sh -s -- -b $(go env GOPATH)/bin latest
        fi
        
        # Run linting for each module
        EXIT_CODE=0
        for module in discovery processor common; do
            echo "🔍 Linting $module..."
            cd $module
            if ! golangci-lint run --timeout 5m; then
                EXIT_CODE=1
            fi
            cd ..
        done
        
        exit $EXIT_CODE
    '''
}