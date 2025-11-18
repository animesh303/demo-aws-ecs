terraform { 
  cloud { 
    
    organization = "aws-devops-ai" 

    workspaces { 
      name = "ecr-demo-ws" 
    } 
  } 
}