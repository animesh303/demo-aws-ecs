# Fixes Applied to Terraform Configuration

## Summary

I've analyzed your Terraform configuration and identified several issues that could prevent your web app from launching. I've applied fixes for the critical issues and created diagnostic tools to help identify remaining problems.

## ✅ Fixes Applied

### 1. Fixed Container Health Check (CRITICAL)

**Problem**: The container health check was using `wget`, which is not available in the `node:18-alpine` base image.

**Fix Applied**:

- Updated `app/Dockerfile` to install `wget` using `apk add --no-cache wget`
- Increased health check timeout from 5 to 10 seconds in `main.tf`
- Increased unhealthy threshold from 2 to 3 for more stability

**Files Modified**:

- `app/Dockerfile` - Added wget installation
- `terraform/main.tf` - Updated health check timeouts and thresholds

### 2. Improved Health Check Configuration

**Changes**:

- ALB target group timeout: 5s → 10s
- ALB unhealthy threshold: 2 → 3
- Container health check timeout: 5s → 10s

## 🔍 Diagnostic Tools Created

### 1. Analysis Document

Created `ANALYSIS.md` with detailed analysis of all potential issues.

### 2. Diagnostic Script

Created `diagnose.sh` - A comprehensive diagnostic tool that checks:

- Terraform state and outputs
- ECR repository and images
- ECS service status and task failures
- ALB target health
- CloudWatch logs

**Usage**:

```bash
cd terraform
./diagnose.sh
```

## 🚨 Most Likely Issues (Check These First)

### Issue #1: Missing ECR Image (MOST COMMON)

**Symptom**: ECS tasks fail to start with "CannotPullContainerError"

**Check**:

```bash
cd terraform
./diagnose.sh
```

**Fix**: Build and push the Docker image:

```bash
cd ../app
docker build -t demo-web-app .
cd ../terraform

# Get ECR repo URL
ECR_REPO=$(terraform output -raw ecr_repository_url)
AWS_REGION=$(terraform output -raw aws_region)

# Login and push
aws ecr get-login-password --region $AWS_REGION | docker login --username AWS --password-stdin $ECR_REPO
docker tag demo-web-app:latest $ECR_REPO:latest
docker push $ECR_REPO:latest

# Force ECS service update
CLUSTER=$(terraform output -raw ecs_cluster_name)
SERVICE=$(terraform output -raw ecs_service_name)
aws ecs update-service --cluster $CLUSTER --service $SERVICE --force-new-deployment --region $AWS_REGION
```

### Issue #2: Tasks Failing Health Checks

**Symptom**: Tasks start but become unhealthy and are stopped

**Check**:

```bash
# View CloudWatch logs
aws logs tail /ecs/demo-web-app --follow --region us-east-1

# Check ECS service events
aws ecs describe-services --cluster demo-web-app-cluster --services demo-web-app-service --region us-east-1 | jq '.services[0].events[]'
```

**Fix**: The Dockerfile fix should resolve this. Rebuild and push the image.

### Issue #3: Security Group Issues

**Symptom**: ALB can't reach containers

**Check**: Verify security group rules allow traffic from ALB to ECS tasks on port 3000.

**Current Configuration**: ✅ Correct - ECS tasks security group allows ingress from ALB security group.

## 📋 Next Steps

1. **Run the diagnostic script**:

   ```bash
   cd terraform
   ./diagnose.sh
   ```

2. **Rebuild and push the Docker image** (with the fixed Dockerfile):

   ```bash
   cd ../app
   docker build -t demo-web-app .
   # Then follow the push steps above
   ```

3. **Force ECS service update** to use the new image:

   ```bash
   aws ecs update-service --cluster demo-web-app-cluster --service demo-web-app-service --force-new-deployment --region us-east-1
   ```

4. **Monitor the deployment**:

   ```bash
   # Watch ECS service
   aws ecs describe-services --cluster demo-web-app-cluster --services demo-web-app-service --region us-east-1 --query 'services[0].{Status:status,Running:runningCount,Desired:desiredCount}'

   # Watch logs
   aws logs tail /ecs/demo-web-app --follow --region us-east-1
   ```

5. **Get the application URL**:
   ```bash
   terraform output alb_url
   ```

## 🔧 Files Modified

1. `app/Dockerfile` - Added wget installation for health checks
2. `terraform/main.tf` - Improved health check timeouts and thresholds
3. `terraform/ANALYSIS.md` - Detailed analysis document (NEW)
4. `terraform/diagnose.sh` - Diagnostic script (NEW)
5. `terraform/FIXES_APPLIED.md` - This file (NEW)

## 📊 Expected Behavior After Fixes

1. ✅ Container health checks will work (wget is now available)
2. ✅ Health checks are more tolerant (longer timeout, higher threshold)
3. ✅ Diagnostic script helps identify remaining issues quickly

## ⚠️ Important Notes

- **You must rebuild and push the Docker image** after the Dockerfile change
- The diagnostic script requires `jq` to be installed: `sudo apt-get install jq` (or `brew install jq` on macOS)
- Make sure AWS credentials are configured: `aws configure` or set environment variables

## 🆘 If Still Not Working

1. Run `./diagnose.sh` and share the output
2. Check CloudWatch logs for specific error messages
3. Verify ECS service events for task failures
4. Ensure the `/health` endpoint returns 200 OK (it should - it's in server.js)
