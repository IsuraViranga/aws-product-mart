import os
import boto3

from env_loader import load_local_env

load_local_env()

# boto3 automatically reads from ~/.aws/credentials
# No hardcoded keys needed
dynamodb = boto3.resource(
    'dynamodb',
    region_name=os.environ.get('AWS_REGION', 'us-east-1')
)

table = dynamodb.Table(os.environ.get('DYNAMODB_TABLE', 'products'))