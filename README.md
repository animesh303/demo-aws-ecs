# Demo Web Application - AWS ECS Fargate

A minimal web application deployed on AWS ECS Fargate using Terraform. This demo includes a simple Node.js Express application containerized and deployed on AWS serverless infrastructure.

## Architecture

- **Application**: Simple Node.js Express web server
- **Container**: Docker container running on ECS Fargate
- **Load Balancer**: Application Load Balancer (ALB)
- **Networking**: VPC with public subnets across 2 availability zones
- **Logging**: CloudWatch Logs
- **Container Registry**: Amazon ECR

## Prerequisites

Before deploying, ensure you have the following installed and configured:

1. **Docker** - Required for building and pushing container images

   - Linux: [Install Docker Engine](https://docs.docker.com/engine/install/)
   - WSL2: Install [Docker Desktop for Windows](https://docs.docker.com/desktop/install/windows-install/) or Docker Engine in WSL2
   - macOS: [Install Docker Desktop](https://docs.docker.com/desktop/install/mac-install/)
   - Verify: `docker --version`

2. **AWS CLI** - Required for AWS operations

   - Install: [AWS CLI Installation Guide](https://aws.amazon.com/cli/)
   - Configure: `aws configure`
   - Verify: `aws --version` and `aws sts get-caller-identity`

3. **Terraform** - Required for infrastructure provisioning

   - Install: [Terraform Downloads](https://www.terraform.io/downloads)
   - Verify: `terraform version`

4. **Node.js 18+** (optional) - Only needed for local testing of the application

## Project Structure

```
.
├── app/                    # Application source code
│   ├── server.js          # Express server
│   ├── package.json       # Node.js dependencies
│   └── Dockerfile         # Container definition
├── terraform/             # Terraform configuration
│   ├── main.tf           # Main infrastructure resources
│   ├── variables.tf      # Variable definitions
│   ├── outputs.tf        # Output values
│   └── terraform.tfvars.example  # Example variables
└── README.md             # This file
```

## Deployment Steps

### 1. Configure Terraform Variables

Copy the example variables file and customize if needed:

```bash
cd terraform
cp terraform.tfvars.example terraform.tfvars
```

Edit `terraform.tfvars` to set your preferred AWS region and other settings.

### 2. Initialize Terraform

```bash
cd terraform
terraform init
```

### 3. Create Infrastructure

First, create the infrastructure (this will create the ECR repository):

```bash
terraform plan
terraform apply
```

After the first apply, note the ECR repository URL from the output.

### 4. Build and Push Docker Image

Build the Docker image:

```bash
cd ../app
docker build -t demo-web-app .
```

Get your AWS account ID and region:

```bash
AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
AWS_REGION=$(terraform -chdir=../terraform output -raw aws_region 2>/dev/null || echo "us-east-1")
ECR_REPO=$(terraform -chdir=../terraform output -raw ecr_repository_url)
```

Login to ECR:

```bash
aws ecr get-login-password --region $AWS_REGION | docker login --username AWS --password-stdin $ECR_REPO
```

Tag and push the image:

```bash
docker tag demo-web-app:latest $ECR_REPO:latest
docker push $ECR_REPO:latest
```

### 5. Update ECS Service

After pushing the image, update the ECS service to use the new image:

```bash
cd ../terraform
terraform apply
```

Or force a new deployment:

```bash
aws ecs update-service --cluster $(terraform output -raw ecs_cluster_name) --service $(terraform output -raw ecs_service_name) --force-new-deployment --region $AWS_REGION
```

### 6. Access the Application

Get the application URL:

```bash
terraform output alb_url
```

Open the URL in your browser. The application should be accessible.

## Quick Deployment Script

For convenience, you can use this script to automate the deployment:

```bash
#!/bin/bash
set -e

echo "Building Docker image..."
cd app
docker build -t demo-web-app .

echo "Getting AWS details..."
cd ../terraform
AWS_REGION=$(terraform output -raw aws_region 2>/dev/null || grep aws_region terraform.tfvars | cut -d'"' -f2)
ECR_REPO=$(terraform output -raw ecr_repository_url)

echo "Logging into ECR..."
aws ecr get-login-password --region $AWS_REGION | docker login --username AWS --password-stdin $ECR_REPO

echo "Tagging and pushing image..."
docker tag demo-web-app:latest $ECR_REPO:latest
docker push $ECR_REPO:latest

echo "Forcing ECS service update..."
CLUSTER=$(terraform output -raw ecs_cluster_name)
SERVICE=$(terraform output -raw ecs_service_name)
aws ecs update-service --cluster $CLUSTER --service $SERVICE --force-new-deployment --region $AWS_REGION

echo "Deployment complete! URL:"
terraform output alb_url
```

## Testing Locally

To test the application locally:

```bash
cd app
npm install
npm start
```

Visit `http://localhost:3000` in your browser.

## Application Endpoints

- `GET /` - Main web page
- `GET /health` - Health check endpoint (returns JSON)

## Cleanup

To destroy all resources:

```bash
cd terraform
terraform destroy
```

**Note**: This will delete all resources including the ECR repository and all images.

## Configuration

Key Terraform variables (in `terraform.tfvars`):

- `aws_region`: AWS region (default: us-east-1)
- `app_name`: Application name (default: demo-web-app)
- `container_cpu`: CPU units (256 = 0.25 vCPU)
- `container_memory`: Memory in MB (default: 512)
- `desired_count`: Number of tasks to run (default: 1)

## Security Notes

This is a minimal demo setup with:

- Public subnets (containers have public IPs)
- HTTP only (no HTTPS/TLS)
- Default security groups (minimal rules)
- No authentication or authorization

For production use, consider:

- Using private subnets with NAT Gateway
- Adding HTTPS/TLS with ACM certificates
- Implementing proper security groups
- Adding authentication/authorization
- Enabling container insights
- Setting up proper logging and monitoring

## Troubleshooting

### Docker Group Does Not Exist

If you see `usermod: group 'docker' does not exist`, Docker is not properly installed.

**For WSL2 users, you have two options:**

**Option 1: Docker Desktop for Windows (Easiest - Recommended)**

1. Download and install [Docker Desktop for Windows](https://www.docker.com/products/docker-desktop/)
2. Open Docker Desktop
3. Go to **Settings → Resources → WSL Integration**
   - Enable integration with your WSL2 distro
   - Click **Apply & Restart**
4. Restart your WSL2 terminal
5. Verify: `docker --version` and `docker ps`

**Option 2: Install Docker Engine in WSL2**

Run the helper script for step-by-step instructions:

```bash
./fix-docker-permissions.sh
```

Or manually install:

```bash
# Update packages
sudo apt-get update

# Install prerequisites
sudo apt-get install -y ca-certificates curl gnupg lsb-release

# Add Docker's official GPG key
sudo mkdir -p /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg

# Set up repository
echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

# Install Docker Engine
sudo apt-get update
sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin

# Start Docker service
sudo service docker start

# Add user to docker group
sudo usermod -aG docker $USER
newgrp docker

# Verify
docker ps
```

### Docker Permission Denied Error

If you see `permission denied while trying to connect to the Docker daemon socket`:

**Option 1: Add user to docker group (Recommended)**

```bash
sudo usermod -aG docker $USER
newgrp docker  # or log out and back in
```

**Option 2: Use the helper script**

```bash
./fix-docker-permissions.sh
```

**Option 3: Use sudo (Not recommended)**

```bash
sudo ./deploy.sh
```

**Option 4: Docker Desktop**

- Make sure Docker Desktop for Windows is running
- Ensure WSL2 integration is enabled in Docker Desktop settings

### Docker Daemon Not Running

If Docker daemon is not running:

- **Docker Desktop**: Start the Docker Desktop application
- **Linux service**: `sudo systemctl start docker`
- **WSL2**: Ensure Docker Desktop is running on Windows

### Container fails to start

- Check CloudWatch logs: `/ecs/demo-web-app`
- Verify the image was pushed correctly to ECR
- Check security group rules allow traffic from ALB

### Cannot access the application

- Verify the ALB DNS name is correct
- Check security groups allow HTTP (port 80) from your IP
- Ensure ECS tasks are running: `aws ecs list-tasks --cluster <cluster-name>`

### Image pull errors

- Verify ECR repository exists
- Check IAM role has permissions to pull from ECR
- Ensure image tag matches what's in the task definition

## License

See LICENSE file for details.
