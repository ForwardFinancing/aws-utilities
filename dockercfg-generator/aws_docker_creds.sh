#!/bin/bash

set -e
AWS_REGION=us-east-1
echo 'AWS ECR dockercfg generator'

: "${AWS_REGION:?Need to set AWS_REGION}"
: "${AWS_ACCESS_KEY_ID:?Need to set AWS_ACCESS_KEY_ID}"
: "${AWS_SECRET_ACCESS_KEY:?Need to set AWS_SECRET_ACCESS_KEY}"

cat << EOF > ~/.aws/config
[default]
region = $AWS_REGION
EOF

# For multi account aws setups, use primary credentials to assume the role in
# the target account
AWS_ACCOUNT=""
if [[ -n $AWS_STS_ROLE || -n $AWS_STS_ACCOUNT ]]; then
  : "${AWS_STS_ROLE:?Need to set AWS_STS_ROLE}"
  : "${AWS_STS_ACCOUNT:?Need to set AWS_STS_ACCOUNT}"

  role="arn:aws:iam::${AWS_STS_ACCOUNT}:role/${AWS_STS_ROLE}"
  echo "Using STS to get credentials for ${role}"

  aws_tmp=$(mktemp -t aws-json-XXXXXX)

  aws sts assume-role --role-arn "${role}" --role-session-name aws_docker_creds > "${aws_tmp}"

  export AWS_ACCESS_KEY_ID=$(cat ${aws_tmp} | jq -r ".Credentials.AccessKeyId")
  export AWS_SECRET_ACCESS_KEY=$(cat ${aws_tmp} | jq -r ".Credentials.SecretAccessKey")
  export AWS_SESSION_TOKEN=$(cat ${aws_tmp} | jq -r ".Credentials.SessionToken")
  export AWS_SESSION_EXPIRATION=$(cat ${aws_tmp} | jq -r ".Credentials.Expiration")

  AWS_ACCOUNT=$AWS_STS_ACCOUNT
else
  AWS_ACCOUNT=$(aws sts get-caller-identity | jq -r ".Account")
fi

# fetching aws docker login
echo "Logging into AWS ECR with Account ${AWS_ACCOUNT}"
# AWS has deprecated the get-login function in favor of get-login-password
# https://docs.aws.amazon.com/cli/latest/reference/ecr/get-login.html
aws ecr get-login-password --region ${AWS_REGION} | docker login --username AWS --password-stdin ${AWS_ACCOUNT}.dkr.ecr.${AWS_REGION}.amazonaws.com

# append existing docker login
EXISTING_DOCKERCFG="/existing-dockercfg"
if [ -f "$EXISTING_DOCKERCFG" ]; then
  cat ~/.docker/config.json | jq --argjson dockercfg "$(cat $EXISTING_DOCKERCFG | jq '.auths')" '.auths += $dockercfg' | jq --argjson httpheaders "$(cat /existing-dockercfg | jq '.HttpHeaders')" '.HttpHeaders += $httpheaders' >> tmp-dockercfg.json
  mv tmp-dockercfg.json ~/.docker/config.json
else 
  echo "$EXISTING_DOCKERCFG does not exist."
fi

# writing aws docker creds to desired path
echo "Writing Docker creds to $1"
chmod 544 ~/.docker/config.json
cp ~/.docker/config.json $1