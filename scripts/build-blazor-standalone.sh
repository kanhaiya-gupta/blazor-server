#!/bin/bash

# AASX Blazor Server Standalone Build Script
# Builds and manages the standalone Blazor server Docker image

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
IMAGE_NAME="aasx-blazor-standalone"
CONTAINER_NAME="aasx-blazor-standalone"
DOCKERFILE_PATH="docker/Dockerfile"
DOCKERFILE_DEV_PATH="docker/Dockerfile.dev"
DOCKER_COMPOSE_PATH="docker/docker-compose.yml"
DATA_DIR="../data"
PORT="5001"

# Function to print colored output
print_header() {
    echo -e "${BLUE}========================================${NC}"
    echo -e "${BLUE}   AASX Blazor Server Standalone${NC}"
    echo -e "${BLUE}========================================${NC}"
    echo
}

print_success() {
    echo -e "${GREEN}✅ $1${NC}"
}

print_warning() {
    echo -e "${YELLOW}⚠️  $1${NC}"
}

print_error() {
    echo -e "${RED}❌ $1${NC}"
}

print_info() {
    echo -e "${BLUE}ℹ️  $1${NC}"
}

# Function to check prerequisites
check_prerequisites() {
    print_info "Checking prerequisites..."
    
    if ! command -v docker &> /dev/null; then
        print_error "Docker is not installed or not in PATH"
        exit 1
    fi
    
    if ! command -v docker-compose &> /dev/null; then
        print_error "Docker Compose is not installed or not in PATH"
        exit 1
    fi
    
    if [ ! -f "$DOCKERFILE_PATH" ]; then
        print_error "Dockerfile not found: $DOCKERFILE_PATH"
        exit 1
    fi
    
    print_success "Prerequisites check passed"
}

# Function to build the image
build_image() {
    local dockerfile=$1
    local tag=$2
    
    print_info "Building Docker image: $IMAGE_NAME:$tag"
    print_info "Using Dockerfile: $dockerfile"
    
    docker build -f "$dockerfile" -t "$IMAGE_NAME:$tag" .
    
    if [ $? -eq 0 ]; then
        print_success "Image built successfully: $IMAGE_NAME:$tag"
    else
        print_error "Failed to build image"
        exit 1
    fi
}

# Function to run the container
run_container() {
    local tag=$1
    
    print_info "Starting container: $CONTAINER_NAME"
    
    # Stop existing container if running
    docker stop "$CONTAINER_NAME" 2>/dev/null || true
    docker rm "$CONTAINER_NAME" 2>/dev/null || true
    
    # Create data directory if it doesn't exist
    mkdir -p "$DATA_DIR"
    
    # Run the container
    docker run -d \
        --name "$CONTAINER_NAME" \
        -p "$PORT:5001" \
        -v "$(pwd)/$DATA_DIR:/app/data" \
        -e AASX_DATA_PATH=./data \
        -e AASX_SERVER_PORT=5001 \
        -e ASPNETCORE_ENVIRONMENT=Production \
        "$IMAGE_NAME:$tag"
    
    if [ $? -eq 0 ]; then
        print_success "Container started successfully"
        print_info "Access the Blazor server at: http://localhost:$PORT"
        print_info "Container name: $CONTAINER_NAME"
    else
        print_error "Failed to start container"
        exit 1
    fi
}

# Function to stop the container
stop_container() {
    print_info "Stopping container: $CONTAINER_NAME"
    
    docker stop "$CONTAINER_NAME" 2>/dev/null || true
    docker rm "$CONTAINER_NAME" 2>/dev/null || true
    
    print_success "Container stopped and removed"
}

# Function to show logs
show_logs() {
    local follow=$1
    
    print_info "Showing logs for container: $CONTAINER_NAME"
    
    if [ "$follow" = "true" ]; then
        docker logs -f "$CONTAINER_NAME"
    else
        docker logs "$CONTAINER_NAME"
    fi
}

# Function to clean up
cleanup() {
    print_info "Cleaning up Docker resources..."
    
    # Stop and remove container
    stop_container
    
    # Remove images
    docker rmi "$IMAGE_NAME:latest" 2>/dev/null || true
    docker rmi "$IMAGE_NAME:dev" 2>/dev/null || true
    
    # Remove dangling images
    docker image prune -f
    
    print_success "Cleanup completed"
}

# Function to show status
show_status() {
    print_info "Container status:"
    docker ps -a --filter "name=$CONTAINER_NAME" --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"
    
    echo
    print_info "Image status:"
    docker images "$IMAGE_NAME" --format "table {{.Repository}}\t{{.Tag}}\t{{.Size}}\t{{.CreatedAt}}"
}

# Function to use docker-compose
use_compose() {
    local action=$1
    
    print_info "Using Docker Compose: $action"
    
    cd docker
    docker-compose $action
    cd ..
}

# Function to show help
show_help() {
    print_header
    echo "Usage: $0 [COMMAND] [OPTIONS]"
    echo
    echo "Commands:"
    echo "  build [dev]     Build the Docker image (dev for development)"
    echo "  run [dev]       Build and run the container (dev for development)"
    echo "  start           Start the container"
    echo "  stop            Stop the container"
    echo "  restart         Restart the container"
    echo "  logs [--follow] Show container logs"
    echo "  status          Show container and image status"
    echo "  clean           Clean up Docker resources"
    echo "  compose [up|down|build] Use docker-compose"
    echo "  help            Show this help message"
    echo
    echo "Options:"
    echo "  --follow        Follow logs (use with logs command)"
    echo "  dev             Use development Dockerfile"
    echo
    echo "Examples:"
    echo "  $0 build        # Build production image"
    echo "  $0 build dev    # Build development image"
    echo "  $0 run          # Build and run production container"
    echo "  $0 run dev      # Build and run development container"
    echo "  $0 logs --follow # Show logs with follow"
    echo "  $0 compose up   # Use docker-compose to start services"
    echo
}

# Main script logic
main() {
    local command=$1
    local option=$2
    
    case "$command" in
        "build")
            check_prerequisites
            if [ "$option" = "dev" ]; then
                build_image "$DOCKERFILE_DEV_PATH" "dev"
            else
                build_image "$DOCKERFILE_PATH" "latest"
            fi
            ;;
        "run")
            check_prerequisites
            if [ "$option" = "dev" ]; then
                build_image "$DOCKERFILE_DEV_PATH" "dev"
                run_container "dev"
            else
                build_image "$DOCKERFILE_PATH" "latest"
                run_container "latest"
            fi
            ;;
        "start")
            check_prerequisites
            run_container "latest"
            ;;
        "stop")
            stop_container
            ;;
        "restart")
            stop_container
            sleep 2
            run_container "latest"
            ;;
        "logs")
            if [ "$option" = "--follow" ]; then
                show_logs "true"
            else
                show_logs "false"
            fi
            ;;
        "status")
            show_status
            ;;
        "clean")
            cleanup
            ;;
        "compose")
            use_compose "$option"
            ;;
        "help"|"--help"|"-h"|"")
            show_help
            ;;
        *)
            print_error "Unknown command: $command"
            echo
            show_help
            exit 1
            ;;
    esac
}

# Run main function with all arguments
main "$@" 