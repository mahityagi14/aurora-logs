def call(Map args = [:]) {
    def version = args.version ?: 'unknown'
    def goos = args.goos ?: 'linux'
    def goarch = args.goarch ?: 'arm64'
    
    sh """
        echo "🔨 Building services version: ${version}"
        
        # Build flags
        BUILD_FLAGS="-ldflags='-w -s -X main.version=${version}'"
        
        # Build discovery service
        echo "Building discovery service..."
        cd discovery
        CGO_ENABLED=0 GOOS=${goos} GOARCH=${goarch} go build \$BUILD_FLAGS -o discovery .
        cd ..
        
        # Build processor service
        echo "Building processor service..."
        cd processor
        CGO_ENABLED=0 GOOS=${goos} GOARCH=${goarch} go build \$BUILD_FLAGS -o processor .
        cd ..
        
        # List built artifacts
        echo "Built artifacts:"
        ls -la discovery/discovery processor/processor
    """
}