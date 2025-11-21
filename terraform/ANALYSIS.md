# Terraform Configuration Analysis

## Issues Identified

### 🔴 Critical Issue #1: Container Health Check Command

**Location**: `main.tf` line 296

**Problem**: The container health check uses `wget` which is not available in the `node:18-alpine` base image.

```terraform
healthCheck = {
  command     = ["CMD-SHELL", "wget --no-verbose --tries=1 --spider http://localhost:${var.container_port}/health || exit 1"]
  ...
}
```

**Impact**: Container health checks will fail, causing tasks to be marked as unhealthy and potentially stopped.

**Solution**: Use `wget` (requires installing it) or switch to `curl` (also requires installation) or use Node.js to check health.

### 🟡 Issue #2: Missing ECR Image

**Location**: `terraform.tfvars` line 8

**Problem**: The `ecr_image` variable is empty, which means Terraform will try to use:

```
${aws_ecr_repository.app.repository_url}:latest
```

**Impact**: If no image has been pushed to ECR, the ECS service cannot start tasks. Tasks will fail with "CannotPullContainerError".

**Solution**:

1. Build and push the Docker image to ECR first
2. Or set the `ecr_image` variable to a valid image URI

### 🟡 Issue #3: Health Check Timeout Configuration

**Location**: `main.tf` lines 151-159

**Problem**: The ALB target group health check has:

- `timeout = 5` seconds
- `interval = 30` seconds
- `healthy_threshold = 2`
- `unhealthy_threshold = 2`

**Impact**: If the container takes longer than 5 seconds to respond, health checks will fail. The thresholds are quite low (2), which might cause flapping.

**Recommendation**: Consider increasing timeout to 10 seconds and thresholds to 3 for more stability.

### 🟢 Issue #4: Container Health Check Start Period

**Location**: `main.tf` line 300

**Current**: `startPeriod = 60` seconds

**Analysis**: This is reasonable for a Node.js app, but if the app takes longer to start, health checks might fail during startup.

## Recommended Fixes

### Fix #1: Update Container Health Check

Replace `wget` with a Node.js-based health check or install `wget` in the Dockerfile.

**Option A**: Install wget in Dockerfile (simpler)
**Option B**: Use Node.js to check health (more reliable)

### Fix #2: Verify ECR Image Exists

Before deploying, ensure an image exists in ECR:

```bash
aws ecr describe-images --repository-name demo-web-app --region us-east-1
```

### Fix #3: Check ECS Service Status

Monitor the ECS service to see actual errors:

```bash
aws ecs describe-services --cluster demo-web-app-cluster --services demo-web-app-service --region us-east-1
```

### Fix #4: Check CloudWatch Logs

View container logs for errors:

```bash
aws logs tail /ecs/demo-web-app --follow --region us-east-1
```

## Common Failure Scenarios

1. **Image Pull Errors**: ECR image doesn't exist or wrong tag
2. **Health Check Failures**: Container health check command fails
3. **ALB Health Check Failures**: Target group health checks fail
4. **Network Issues**: Security groups blocking traffic
5. **Resource Constraints**: Insufficient CPU/memory

## Next Steps

1. Fix the container health check command
2. Verify ECR image exists and is pushed
3. Check ECS service events for specific errors
4. Review CloudWatch logs for application errors
5. Verify security group rules are correct
