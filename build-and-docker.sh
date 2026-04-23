#!/bin/bash
# build-and-docker.sh
# Bouwt llama-swap met custom endpoints en maakt een Docker image
# 
# Gebruik: ./build-and-docker.sh
#
# Dit script:
# 1. Bouwt de Go binary voor Linux
# 2. Bouwt een Docker image
# 3. Tag het image voor push

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# Configurable variables
IMAGE_NAME="${IMAGE_NAME:-llama-swap-custom}"
IMAGE_TAG="${IMAGE_TAG:-latest}"
BUILD_PLATFORM="${BUILD_PLATFORM:-linux/amd64}"

echo "=========================================="
echo "Building llama-swap with custom endpoints"
echo "=========================================="
echo "Image: $IMAGE_NAME:$IMAGE_TAG"
echo "Platform: $BUILD_PLATFORM"
echo ""

# Step 1: Build the Go binary for Linux
echo "Step 1: Building Go binary for Linux..."
mkdir -p build

# Build for Linux (cross-compile from Windows or native on Linux)
CGO_ENABLED=0 GOOS=linux GOARCH=amd64 go build -o build/llama-swap-linux-amd64 .

echo "✅ Binary built: build/llama-swap-linux-amd64"
echo ""

# Step 2: Build Docker image
echo "Step 2: Building Docker image..."

# Check if Dockerfile exists
if [ ! -f "docker/llama-swap.Containerfile" ]; then
    echo "❌ Dockerfile not found: docker/llama-swap.Containerfile"
    exit 1
fi

# Build the image
docker build \
    --platform "$BUILD_PLATFORM" \
    -t "$IMAGE_NAME:$IMAGE_TAG" \
    -f docker/llama-swap.Containerfile \
    --build-arg BINARY_PATH=../build/llama-swap-linux-amd64 \
    .

echo "✅ Docker image built: $IMAGE_NAME:$IMAGE_TAG"
echo ""

# Step 3: Show image info
echo "=========================================="
echo "Image built successfully!"
echo "=========================================="
echo "Image: $IMAGE_NAME:$IMAGE_TAG"
echo ""
echo "To push to registry:"
echo "  docker push $IMAGE_NAME:$IMAGE_TAG"
echo ""
echo "To run locally:"
echo "  docker run -d -p 8080:8080 -v ./config.yaml:/etc/llama-swap/config.yaml $IMAGE_NAME:$IMAGE_TAG"
echo ""