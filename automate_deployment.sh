# Prerequisites:
# - Set up .aws/credentials profiles for pipeline, uat, and prod
# - Set TOOLS_ACCOUNT_ID, UAT_ACCOUNT_ID and PROD_ACCOUNT_ID env variables
# - Clone repo with Cloudformation template and CDK code locally
# - Initialize and bootstrap CDK in the Tools account
# - Install and configure git

# if prerequisite account values aren't set, exit
if [[ -z "${TOOLS_ACCOUNT_ID}" || -z "${UAT_ACCOUNT_ID}" || -z "${PROD_ACCOUNT_ID}" ]]; then
  printf "Please set TOOLS_ACCOUNT_ID, UAT_ACCOUNT_ID and PROD_ACCOUNT_ID"
  printf "TOOLS_ACCOUNT_ID =" ${TOOLS_ACCOUNT_ID}
  printf "UAT_ACCOUNT_ID =" ${UAT_ACCOUNT_ID}
  printf "PROD_ACCOUNT_ID =" ${PROD_ACCOUNT_ID}
  exit
fi

# Deploy roles without policies so the ARNs exist when the CDK Stack is deployed
printf "\nDeploying roles to UAT and Prod\n"
aws cloudformation deploy --template-file templates/CodePipelineCrossAccountRole.yml \
    --stack-name CodepipelineCrossAccountRole \
    --capabilities CAPABILITY_NAMED_IAM \
    --profile orsis_dev \
    --parameter-overrides ToolsAccountID=${TOOLS_ACCOUNT_ID} &

aws cloudformation deploy --template-file templates/CloudFormationDeploymentRole.yml \
    --stack-name CloudFormationDeploymentRole \
    --capabilities CAPABILITY_NAMED_IAM \
    --profile orsis_dev \
    --parameter-overrides ToolsAccountID=${TOOLS_ACCOUNT_ID} Stage=Uat &

aws cloudformation deploy --template-file templates/CodePipelineCrossAccountRole.yml \
    --stack-name CodepipelineCrossAccountRole \
    --capabilities CAPABILITY_NAMED_IAM \
    --profile orsis_prod \
    --parameter-overrides ToolsAccountID=${TOOLS_ACCOUNT_ID} &

aws cloudformation deploy --template-file templates/CloudFormationDeploymentRole.yml \
    --stack-name CloudFormationDeploymentRole \
    --capabilities CAPABILITY_NAMED_IAM \
    --profile orsis_prod \
    --parameter-overrides ToolsAccountID=${TOOLS_ACCOUNT_ID} Stage=Prod &



# Deploy Repository CDK Stack
printf "\nDeploying Repository Stack\n"
npm install
npm audit &
npm run build
cdk synth
cdk deploy RepositoryStack --profile orsis_DevOps

# Deploy Pipeline CDK stack, write output to a file to gather key arn
printf "\nDeploying Cross-Account Deployment Pipeline Stack\n"

CDK_OUTPUT_FILE='.cdk_output'
rm -rf ${CDK_OUTPUT_FILE} .cfn_outputs
npx cdk deploy CrossAccountPipelineStack \
  --context prod-account=${PROD_ACCOUNT_ID}
  --context uat-account=${UAT_ACCOUNT_ID}
  -profile orsis_DevOps
  --require-approval never \
  2>&1 | tee -a ${CDK_OUTPUT_FILE}
sed -n -e '/Outputs:/,/^$/ p' ${CDK_OUTPUT_FILE} > .cfn_outputs
KEY_ARN=$(aws -F " " 'KeyArn/ { print $3 }' .cfn_outputs )

# Check the KEY_ARN is set after the CDK deployment
if [[ -z "${KEY_ARN}" ]]; then
  printf "\nSomething went wrong - we didn't get a Key ARN as an output from the CDK Pipeline deployment"
  exit
fi

# Update the Cloudformation roles with the Key ARN
print "\nUpdating roles with policies in UAT and Prod\n"
aws cloudformation deploy --template-file templates/CodepipelineCrossAccountRole.yml \
    --stack-name CodepipelineCrossAccountRole \
    --capabilities CAPABILITY_NAMED_IAM \
    --profile orsis_dev \
    --parameter-overrides ToolsAccountID=${TOOLS_ACCOUNT_ID} &

aws cloudformation deploy --template-file templates/CloudFormationDeploymentRole.yml \
    --stack-name CloudFormationDeploymentRole \
    --capabilities CAPABILITY_NAMED_IAM \
    --profile orsis_dev \
    --parameter-overrides ToolsAccountID=${TOOLS_ACCOUNT_ID} Stage=Uat &

aws cloudformation deploy --template-file templates/CodePipelineCrossAccountRole.yml \
    --stack-name CodepipelineCrossAccountRole \
    --capabilities CAPABILITY_NAMED_IAM \
    --profile orsis_prod \
    --parameter-overrides ToolsAccountID=${TOOLS_ACCOUNT_ID} &

aws cloudformation deploy --template-file templates/CloudFormationDeploymentRole.yml \
    --stack-name CloudFormationDeploymentRole \
    --capabilities CAPABILITY_NAMED_IAM \
    --profile orsis_prod \
    --parameter-overrides ToolsAccountID=${TOOLS_ACCOUNT_ID} Stage=Prod &

# Commit initial code to new repo (which will trigger a fresh pipeline execution)
printf "\nCommiting code to repository\n"
git init && git branch -m main && git add . && git commit -m "Initial commit" && git remote rm origin
git remote add origin {url to repo with -${TOOLS_ACCOUNT_ID}}
git config main.remove origin && git config. main.merge refs/heads/main && git push --set-upstream origin main

# Get deployed API Gateway endpoints
printf "\nUse the following commands to get the Endpoints for deployed Environments:"
printf "\n aws cloudformation describe-stacks --stack-name UatApplicationDeploymentStack \
       --profile {aquí uat profile} | grep OutputValue"
printf "\n aws cloudformation describe-stacks --stack-name ProdApplicationDeploymentStack \
       --profile {aquí prod profile} | grep OutputValue"

# Clean up temporary file
rm ${CDK_OUTPUT_FILE} .cfn_outputs

