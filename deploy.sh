#!/bin/bash
set -e

echo "🚀 Starting deployment process..."

# Get the directory of this script
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
cd "$SCRIPT_DIR"

# Check prerequisites
echo "🔍 Checking prerequisites..."

check_command() {
    if ! command -v "$1" &> /dev/null; then
        echo "❌ Error: $1 is not installed or not in PATH"
        case "$1" in
            docker)
                echo ""
                echo "   Docker installation instructions:"
                echo "   - Linux: https://docs.docker.com/engine/install/"
                echo "   - WSL2: Install Docker Desktop for Windows or Docker Engine in WSL2"
                echo "   - macOS: https://docs.docker.com/desktop/install/mac-install/"
                ;;
            aws)
                echo ""
                echo "   AWS CLI installation: https://aws.amazon.com/cli/"
                ;;
            terraform)
                echo ""
                echo "   Terraform installation: https://www.terraform.io/downloads"
                ;;
        esac
        echo ""
        exit 1
    fi
}

check_command "docker"
check_command "aws"
check_command "terraform"

# Check Docker daemon and permissions
echo "🐳 Checking Docker daemon..."

# First check if Docker is installed
if ! command -v docker &> /dev/null; then
    echo "❌ Error: Docker is not installed"
    echo ""
    echo "   For WSL2, you need to either:"
    echo "   1. Install Docker Desktop for Windows (recommended)"
    echo "      https://www.docker.com/products/docker-desktop/"
    echo "      Then enable WSL2 integration in Docker Desktop settings"
    echo ""
    echo "   2. Install Docker Engine in WSL2"
    echo "      Run: ./fix-docker-permissions.sh for detailed instructions"
    echo ""
    exit 1
fi

# Check if docker group exists
if ! getent group docker &> /dev/null 2>&1; then
    echo "❌ Error: Docker group does not exist"
    echo ""
    echo "   This usually means Docker Engine is not properly installed."
    echo ""
    echo "   If using Docker Desktop:"
    echo "   - Make sure Docker Desktop is running on Windows"
    echo "   - Enable WSL2 integration in Docker Desktop settings"
    echo "   - Restart your WSL2 terminal"
    echo ""
    echo "   For installation help, run: ./fix-docker-permissions.sh"
    echo ""
    exit 1
fi

# Check Docker daemon accessibility
if ! docker info &> /dev/null; then
    DOCKER_ERROR=$(docker info 2>&1)
    if echo "$DOCKER_ERROR" | grep -q "permission denied"; then
        echo "❌ Error: Docker permission denied"
        echo ""
        echo "   The docker group exists but your user is not a member."
        echo ""
        echo "   To fix:"
        echo "   sudo usermod -aG docker $USER"
        echo "   newgrp docker  # or log out and back in"
        echo ""
        echo "   Or run: ./fix-docker-permissions.sh for help"
        echo ""
        exit 1
    elif echo "$DOCKER_ERROR" | grep -q "Cannot connect to the Docker daemon"; then
        echo "❌ Error: Docker daemon is not running"
        echo ""
        echo "   Please start Docker:"
        echo "   - Docker Desktop: Start the application on Windows"
        echo "   - Docker Engine: sudo service docker start"
        echo ""
        exit 1
    else
        echo "❌ Error: Cannot connect to Docker"
        echo "   Error details: $DOCKER_ERROR"
        echo ""
        echo "   Run: ./fix-docker-permissions.sh for troubleshooting help"
        exit 1
    fi
fi

# Check AWS credentials
echo "🔐 Checking AWS credentials..."
if ! aws sts get-caller-identity &> /dev/null; then
    echo "❌ Error: AWS credentials not configured"
    echo "   Please run 'aws configure' or set AWS credentials"
    exit 1
fi

echo "✅ All prerequisites met"
echo ""

# Step 1: Build Docker image
echo "📦 Building Docker image..."
cd app
if ! docker build -t demo-web-app .; then
    echo "❌ Error: Failed to build Docker image"
    exit 1
fi
cd ..

# Step 2: Initialize Terraform if needed
echo "🔧 Checking Terraform..."
cd terraform

# Check if terraform.tfvars exists
if [ ! -f "terraform.tfvars" ]; then
    echo "⚠️  Warning: terraform.tfvars not found"
    echo "   Creating terraform.tfvars from example..."
    cp terraform.tfvars.example terraform.tfvars
    echo "   Please review terraform.tfvars and adjust if needed"
    echo ""
fi

if [ ! -d ".terraform" ]; then
    echo "Initializing Terraform..."
    terraform init
fi

# Step 3: Apply Terraform to create infrastructure
echo "🏗️  Creating/updating infrastructure..."
terraform apply -auto-approve

# Step 4: Get AWS details
echo "📋 Retrieving infrastructure details..."
AWS_REGION=$(terraform output -raw aws_region 2>/dev/null || grep -E '^\s*aws_region' terraform.tfvars 2>/dev/null | head -1 | sed 's/.*= *"\(.*\)".*/\1/' || echo "us-east-1")
ECR_REPO=$(terraform output -raw ecr_repository_url 2>/dev/null)
CLUSTER=$(terraform output -raw ecs_cluster_name 2>/dev/null)
SERVICE=$(terraform output -raw ecs_service_name 2>/dev/null)

if [ -z "$ECR_REPO" ] || [ -z "$CLUSTER" ] || [ -z "$SERVICE" ]; then
    echo "❌ Error: Failed to retrieve Terraform outputs"
    echo "   Please check that terraform apply completed successfully"
    exit 1
fi

echo "📍 AWS Region: $AWS_REGION"
echo "📦 ECR Repository: $ECR_REPO"
echo "🏢 ECS Cluster: $CLUSTER"
echo "⚙️  ECS Service: $SERVICE"

# Step 5: Login to ECR
echo "🔐 Logging into ECR..."
if ! aws ecr get-login-password --region $AWS_REGION | docker login --username AWS --password-stdin $ECR_REPO; then
    echo "❌ Error: Failed to login to ECR"
    echo "   Please check your AWS credentials and ECR repository"
    exit 1
fi

# Step 6: Tag and push image
echo "📤 Tagging and pushing Docker image..."
docker tag demo-web-app:latest $ECR_REPO:latest
if ! docker push $ECR_REPO:latest; then
    echo "❌ Error: Failed to push Docker image to ECR"
    exit 1
fi

# Step 7: Force ECS service update
echo "🔄 Updating ECS service..."
if ! aws ecs update-service --cluster $CLUSTER --service $SERVICE --force-new-deployment --region $AWS_REGION > /dev/null; then
    echo "❌ Error: Failed to update ECS service"
    exit 1
fi

# Step 8: Wait for service to stabilize
echo "⏳ Waiting for service to stabilize (this may take a few minutes)..."
if ! aws ecs wait services-stable --cluster $CLUSTER --services $SERVICE --region $AWS_REGION; then
    echo "⚠️  Warning: Service did not stabilize within expected time"
    echo "   Check ECS console or CloudWatch logs for details"
fi

# Step 9: Get application URL
echo ""
echo "✅ Deployment complete!"
echo ""
echo "🌐 Application URL:"
terraform output alb_url
echo ""
echo "📊 View logs:"
echo "   aws logs tail /ecs/demo-web-app --follow --region $AWS_REGION"
echo ""

