- arm64 throughout the whole project for cost saving
- eks pod identity, no irsa/oidc
- fluentbit to follow opensearch log format for timestamp consistency
- ignore/remove eks fargate or master salve
- openobserve to be accesed through openobserv-alb that is already created
- use the exisitng ALB - openobserve-alb - arn:aws:elasticloadbalancing:us-east-1:072006186126:loadbalancer/app/openobserve-alb/e5b34856b41f3d36
 


