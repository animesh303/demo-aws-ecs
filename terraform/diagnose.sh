#!/bin/bash
# Diagnostic script to check ECS deployment status

set -e

echo "🔍 ECS Deployment Diagnostic Tool"
echo "=================================="
echo ""

# Get variables from terraform
cd "$(dirname "$0")"

if [ ! -f "terraform.tfvars" ]; then
    echo "❌ Error: terraform.tfvars not found"
    exit 1
fi

AWS_REGION=$(grep -E '^\s*aws_region' terraform.tfvars 2>/dev/null | head -1 | sed 's/.*= *"\(.*\)".*/\1/' || echo "us-east-1")
APP_NAME=$(grep -E '^\s*app_name' terraform.tfvars 2>/dev/null | head -1 | sed 's/.*= *"\(.*\)".*/\1/' || echo "demo-web-app")

echo "📍 Configuration:"
echo "   Region: $AWS_REGION"
echo "   App Name: $APP_NAME"
echo ""

# Check if terraform outputs are available
echo "1️⃣  Checking Terraform State..."
if ! terraform output -json > /dev/null 2>&1; then
    echo "   ⚠️  Warning: Terraform state not initialized or outputs not available"
    echo "   Run: terraform init && terraform apply"
    echo ""
else
    CLUSTER=$(terraform output -raw ecs_cluster_name 2>/dev/null || echo "")
    SERVICE=$(terraform output -raw ecs_service_name 2>/dev/null || echo "")
    ECR_REPO=$(terraform output -raw ecr_repository_url 2>/dev/null || echo "")
    ALB_DNS=$(terraform output -raw alb_dns_name 2>/dev/null || echo "")
    
    echo "   ✅ Terraform outputs available"
    echo "   Cluster: $CLUSTER"
    echo "   Service: $SERVICE"
    echo "   ECR Repo: $ECR_REPO"
    echo ""
fi

# Check ECR images
echo "2️⃣  Checking ECR Repository..."
if [ -n "$ECR_REPO" ]; then
    REPO_NAME=$(echo $ECR_REPO | sed 's|.*/||')
    IMAGES=$(aws ecr describe-images --repository-name "$REPO_NAME" --region "$AWS_REGION" --query 'imageDetails[*].imageTags[0]' --output text 2>/dev/null || echo "")
    
    if [ -z "$IMAGES" ] || [ "$IMAGES" == "None" ]; then
        echo "   ❌ CRITICAL: No images found in ECR repository!"
        echo "   This is likely why your app won't launch."
        echo "   Solution: Build and push the Docker image:"
        echo "      cd ../app"
        echo "      docker build -t $APP_NAME ."
        echo "      aws ecr get-login-password --region $AWS_REGION | docker login --username AWS --password-stdin $ECR_REPO"
        echo "      docker tag $APP_NAME:latest $ECR_REPO:latest"
        echo "      docker push $ECR_REPO:latest"
        echo ""
    else
        echo "   ✅ Images found: $IMAGES"
        echo ""
    fi
else
    echo "   ⚠️  Cannot check ECR - repository URL not available"
    echo ""
fi

# Check ECS Service
echo "3️⃣  Checking ECS Service Status..."
if [ -n "$CLUSTER" ] && [ -n "$SERVICE" ]; then
    SERVICE_INFO=$(aws ecs describe-services --cluster "$CLUSTER" --services "$SERVICE" --region "$AWS_REGION" 2>/dev/null || echo "")
    
    if [ -z "$SERVICE_INFO" ]; then
        echo "   ❌ Service not found or AWS credentials not configured"
        echo ""
    else
        DESIRED=$(echo "$SERVICE_INFO" | jq -r '.services[0].desiredCount // "N/A"')
        RUNNING=$(echo "$SERVICE_INFO" | jq -r '.services[0].runningCount // "N/A"')
        PENDING=$(echo "$SERVICE_INFO" | jq -r '.services[0].pendingCount // "N/A"')
        STATUS=$(echo "$SERVICE_INFO" | jq -r '.services[0].status // "N/A"')
        
        echo "   Desired Tasks: $DESIRED"
        echo "   Running Tasks: $RUNNING"
        echo "   Pending Tasks: $PENDING"
        echo "   Status: $STATUS"
        echo ""
        
        if [ "$RUNNING" == "0" ] && [ "$DESIRED" != "0" ]; then
            echo "   ⚠️  WARNING: No tasks are running but tasks are desired!"
            echo "   Checking task failures..."
            echo ""
            
            # Get recent task failures
            TASKS=$(aws ecs list-tasks --cluster "$CLUSTER" --service-name "$SERVICE" --desired-status STOPPED --region "$AWS_REGION" --max-items 5 --query 'taskArns[]' --output text 2>/dev/null || echo "")
            
            if [ -n "$TASKS" ] && [ "$TASKS" != "None" ]; then
                echo "   Recent stopped tasks:"
                for TASK in $TASKS; do
                    TASK_DETAILS=$(aws ecs describe-tasks --cluster "$CLUSTER" --tasks "$TASK" --region "$AWS_REGION" 2>/dev/null || echo "")
                    STOPPED_REASON=$(echo "$TASK_DETAILS" | jq -r '.tasks[0].stoppedReason // "N/A"' 2>/dev/null || echo "N/A")
                    EXIT_CODE=$(echo "$TASK_DETAILS" | jq -r '.tasks[0].containers[0].exitCode // "N/A"' 2>/dev/null || echo "N/A")
                    echo "      Task: $(basename $TASK)"
                    echo "         Reason: $STOPPED_REASON"
                    echo "         Exit Code: $EXIT_CODE"
                done
                echo ""
            fi
        fi
    fi
else
    echo "   ⚠️  Cannot check ECS service - cluster/service names not available"
    echo ""
fi

# Check ALB Target Health
echo "4️⃣  Checking ALB Target Health..."
if [ -n "$ALB_DNS" ]; then
    ALB_ARN=$(aws elbv2 describe-load-balancers --region "$AWS_REGION" --query "LoadBalancers[?DNSName=='$ALB_DNS'].LoadBalancerArn" --output text 2>/dev/null || echo "")
    
    if [ -n "$ALB_ARN" ] && [ "$ALB_ARN" != "None" ]; then
        TG_ARN=$(aws elbv2 describe-target-groups --load-balancer-arn "$ALB_ARN" --region "$AWS_REGION" --query 'TargetGroups[0].TargetGroupArn' --output text 2>/dev/null || echo "")
        
        if [ -n "$TG_ARN" ] && [ "$TG_ARN" != "None" ]; then
            HEALTH=$(aws elbv2 describe-target-health --target-group-arn "$TG_ARN" --region "$AWS_REGION" 2>/dev/null || echo "")
            
            if [ -n "$HEALTH" ]; then
                TARGETS=$(echo "$HEALTH" | jq -r '.TargetHealthDescriptions[] | "\(.Target.Id): \(.TargetHealth.State)"' 2>/dev/null || echo "")
                
                if [ -z "$TARGETS" ]; then
                    echo "   ⚠️  No targets registered with the target group"
                else
                    echo "   Target Health:"
                    echo "$TARGETS" | while read line; do
                        if echo "$line" | grep -q "healthy"; then
                            echo "      ✅ $line"
                        else
                            echo "      ❌ $line"
                        fi
                    done
                fi
                echo ""
            fi
        fi
    fi
else
    echo "   ⚠️  Cannot check ALB - DNS name not available"
    echo ""
fi

# Check CloudWatch Logs
echo "5️⃣  Checking Recent CloudWatch Logs..."
if [ -n "$APP_NAME" ]; then
    LOG_GROUP="/ecs/$APP_NAME"
    
    if aws logs describe-log-streams --log-group-name "$LOG_GROUP" --region "$AWS_REGION" --order-by LastEventTime --descending --max-items 1 > /dev/null 2>&1; then
        echo "   ✅ Log group exists: $LOG_GROUP"
        echo "   View logs with:"
        echo "      aws logs tail $LOG_GROUP --follow --region $AWS_REGION"
        echo ""
        
        # Get recent log events
        RECENT_LOGS=$(aws logs tail "$LOG_GROUP" --since 10m --region "$AWS_REGION" 2>/dev/null | tail -20 || echo "")
        
        if [ -n "$RECENT_LOGS" ]; then
            echo "   Recent log entries (last 10 minutes):"
            echo "$RECENT_LOGS" | head -10
            echo ""
        fi
    else
        echo "   ⚠️  Log group not found or no logs yet: $LOG_GROUP"
        echo ""
    fi
fi

echo "=================================="
echo "✅ Diagnostic complete!"
echo ""
echo "💡 Common Solutions:"
echo "   1. If no ECR image: Build and push Docker image"
echo "   2. If tasks failing: Check CloudWatch logs for errors"
echo "   3. If health checks failing: Verify /health endpoint works"
echo "   4. If service not updating: Force new deployment:"
echo "      aws ecs update-service --cluster $CLUSTER --service $SERVICE --force-new-deployment --region $AWS_REGION"
echo ""

