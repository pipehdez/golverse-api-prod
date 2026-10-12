import boto3
import json
import os
from botocore.exceptions import ClientError

def setup_minio():
    endpoint = os.getenv('MINIO_ENDPOINT', 'localhost:9000')
    access_key = os.getenv('MINIO_ROOT_USER', 'minioadmin')
    secret_key = os.getenv('MINIO_ROOT_PASSWORD', 'minioadmin')
    bucket_name = os.getenv('MINIO_BUCKET_NAME', 'fafi-media-dev')
    
    # Use 'http://' prefix if not present
    if not endpoint.startswith('http'):
        endpoint = f"http://{endpoint}"
        
    s3 = boto3.client(
        's3',
        endpoint_url=endpoint,
        aws_access_key_id=access_key,
        aws_secret_access_key=secret_key,
        region_name='us-east-1' # MinIO usually ignores this but boto3 needs it
    )
    
    # Create bucket if it doesn't exist
    try:
        s3.head_bucket(Bucket=bucket_name)
        print(f"Bucket {bucket_name} already exists.")
    except ClientError:
        print(f"Creating bucket {bucket_name}...")
        s3.create_bucket(Bucket=bucket_name)
        
    # Set public read policy
    public_policy = {
        "Version": "2012-10-17",
        "Statement": [
            {
                "Effect": "Allow",
                "Principal": {"AWS": ["*"]},
                "Action": ["s3:GetBucketLocation", "s3:ListBucket"],
                "Resource": [f"arn:aws:s3:::{bucket_name}"]
            },
            {
                "Effect": "Allow",
                "Principal": {"AWS": ["*"]},
                "Action": ["s3:GetObject"],
                "Resource": [f"arn:aws:s3:::{bucket_name}/*"]
            }
        ]
    }
    
    print(f"Setting public policy for bucket {bucket_name}...")
    s3.put_bucket_policy(Bucket=bucket_name, Policy=json.dumps(public_policy))
    print("MiniO configuration completed.")

if __name__ == "__main__":
    setup_minio()
