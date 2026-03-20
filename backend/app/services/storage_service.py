"""S3/MinIO storage abstraction for recordings."""

import logging
from io import BytesIO

import boto3
from botocore.config import Config
from botocore.exceptions import ClientError

from app.config import settings

logger = logging.getLogger(__name__)


class StorageService:
    def __init__(self):
        self.client = boto3.client(
            "s3",
            endpoint_url=settings.S3_ENDPOINT_URL,
            aws_access_key_id=settings.S3_ACCESS_KEY,
            aws_secret_access_key=settings.S3_SECRET_KEY,
            region_name=settings.S3_REGION,
            config=Config(signature_version="s3v4"),
        )
        self.bucket = settings.S3_BUCKET_RECORDINGS

    def ensure_bucket(self) -> None:
        """Create the recordings bucket if it doesn't exist."""
        try:
            self.client.head_bucket(Bucket=self.bucket)
        except ClientError:
            self.client.create_bucket(Bucket=self.bucket)
            logger.info("Created S3 bucket: %s", self.bucket)

    def upload_file(self, key: str, data: bytes, content_type: str = "audio/mp4") -> str:
        """Upload a file to S3. Returns the S3 key."""
        self.client.put_object(
            Bucket=self.bucket,
            Key=key,
            Body=data,
            ContentType=content_type,
            ServerSideEncryption="AES256",
        )
        return key

    def download_file(self, key: str) -> bytes:
        """Download a file from S3."""
        response = self.client.get_object(Bucket=self.bucket, Key=key)
        return response["Body"].read()

    def get_presigned_url(self, key: str, expires_in: int = 900) -> str:
        """Generate a presigned URL for temporary access (default 15 min)."""
        return self.client.generate_presigned_url(
            "get_object",
            Params={"Bucket": self.bucket, "Key": key},
            ExpiresIn=expires_in,
        )

    def delete_file(self, key: str) -> None:
        """Delete a file from S3."""
        self.client.delete_object(Bucket=self.bucket, Key=key)

    def file_exists(self, key: str) -> bool:
        """Check if a file exists in S3."""
        try:
            self.client.head_object(Bucket=self.bucket, Key=key)
            return True
        except ClientError:
            return False

    @staticmethod
    def recording_key(session_id: int) -> str:
        """Generate the S3 key for a session recording."""
        return f"recordings/session_{session_id}/audio.mp4"


storage_service = StorageService()
