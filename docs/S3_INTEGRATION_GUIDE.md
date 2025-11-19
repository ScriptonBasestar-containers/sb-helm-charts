# S3 Storage Integration Guide

This guide explains how to integrate S3-compatible object storage (MinIO or other providers) with applications in the sb-helm-charts repository.

## Table of Contents

- [Overview](#overview)
- [MinIO Setup](#minio-setup)
- [Application Integration](#application-integration)
  - [Immich](#immich-photo--video-storage)
  - [Paperless-ngx](#paperless-ngx-document-storage)
  - [Nextcloud](#nextcloud-primary-storage)
- [SDK Examples](#sdk-examples)
- [Security](#security)
- [Troubleshooting](#troubleshooting)

## Overview

S3-compatible object storage provides scalable, cost-effective storage for large files like photos, videos, and documents. This guide covers:

- **MinIO**: Self-hosted S3-compatible storage (charts/minio)
- **External S3**: AWS S3, DigitalOcean Spaces, Backblaze B2, etc.

### Benefits

- **Scalability**: Separate storage from application compute
- **Cost-effective**: Lower storage costs compared to block storage
- **Redundancy**: Built-in replication and erasure coding (MinIO distributed mode)
- **Multi-application**: Share storage across multiple applications
- **Backup-friendly**: Easy integration with backup tools

## MinIO Setup

### Deploy MinIO

Choose a deployment scenario:

```bash
# Home server (single node, 2 drives)
helm install minio sb-charts/minio \
  -f https://raw.githubusercontent.com/scriptonbasestar-container/sb-helm-charts/master/charts/minio/values-home-single.yaml \
  --set minio.rootPassword=your-secure-password

# Production distributed (4 nodes, 16 drives total)
helm install minio sb-charts/minio \
  -f https://raw.githubusercontent.com/scriptonbasestar-container/sb-helm-charts/master/charts/minio/values-prod-distributed.yaml \
  --set minio.rootPassword=your-secure-password
```

See [MinIO Chart README](../charts/minio/README.md) for complete documentation.

### Create Buckets

Using MinIO Client (mc):

```bash
# Setup alias
export MINIO_ROOT_USER=$(kubectl get secret minio-secret -o jsonpath='{.data.root-user}' | base64 -d)
export MINIO_ROOT_PASSWORD=$(kubectl get secret minio-secret -o jsonpath='{.data.root-password}' | base64 -d)

kubectl port-forward svc/minio 9000:9000 &
mc alias set myminio http://localhost:9000 $MINIO_ROOT_USER $MINIO_ROOT_PASSWORD

# Create buckets
mc mb myminio/immich-media
mc mb myminio/paperless-documents
mc mb myminio/nextcloud-data

# Set versioning (optional)
mc version enable myminio/immich-media
```

### Create Application Users

Best practice: Create dedicated users for each application.

```bash
# Create user for Immich
mc admin user add myminio immich-user immich-secure-password
mc admin policy attach myminio readwrite --user immich-user

# Or create custom policy
cat > immich-policy.json <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": ["s3:*"],
      "Resource": ["arn:aws:s3:::immich-media/*"]
    }
  ]
}
EOF
mc admin policy create myminio immich-policy immich-policy.json
mc admin policy attach myminio immich-policy --user immich-user
```

## Application Integration

### Immich (Photo & Video Storage)

Immich can use S3 for storing uploaded photos and videos.

#### Configuration

Add to `values.yaml`:

```yaml
immich:
  server:
    extraEnv:
      # S3 Configuration
      - name: IMMICH_MEDIA_LOCATION
        value: "s3"
      - name: AWS_ACCESS_KEY_ID
        valueFrom:
          secretKeyRef:
            name: immich-s3-credentials
            key: access-key-id
      - name: AWS_SECRET_ACCESS_KEY
        valueFrom:
          secretKeyRef:
            name: immich-s3-credentials
            key: secret-access-key
      - name: AWS_ENDPOINT
        value: "http://minio.default.svc.cluster.local:9000"
      - name: AWS_REGION
        value: "us-east-1"
      - name: AWS_S3_BUCKET
        value: "immich-media"
      - name: AWS_S3_FORCE_PATH_STYLE
        value: "true"
```

#### Create Credentials Secret

```bash
kubectl create secret generic immich-s3-credentials \
  --from-literal=access-key-id=immich-user \
  --from-literal=secret-access-key=immich-secure-password
```

#### Verification

```bash
# Check Immich logs
kubectl logs -l app=immich-server | grep -i s3

# Upload a test photo and verify in MinIO
mc ls myminio/immich-media/
```

### Paperless-ngx (Document Storage)

Paperless-ngx can store documents in S3 instead of local PVCs.

#### Configuration

Add to `values.yaml`:

```yaml
paperless:
  extraEnv:
    # S3 Document Storage
    - name: PAPERLESS_DBHOST
      value: "postgres.default.svc.cluster.local"
    - name: PAPERLESS_ENABLE_HTTP_REMOTE_USER
      value: "false"

    # S3 Configuration
    - name: PAPERLESS_STORAGE_TYPE
      value: "s3"
    - name: PAPERLESS_AWS_ACCESS_KEY_ID
      valueFrom:
        secretKeyRef:
          name: paperless-s3-credentials
          key: access-key-id
    - name: PAPERLESS_AWS_SECRET_ACCESS_KEY
      valueFrom:
        secretKeyRef:
          name: paperless-s3-credentials
          key: secret-access-key
    - name: PAPERLESS_AWS_STORAGE_BUCKET_NAME
      value: "paperless-documents"
    - name: PAPERLESS_AWS_S3_ENDPOINT_URL
      value: "http://minio.default.svc.cluster.local:9000"
    - name: PAPERLESS_AWS_S3_REGION_NAME
      value: "us-east-1"
```

#### PVC Configuration

When using S3, reduce PVC sizes:

```yaml
persistence:
  data:
    size: 5Gi      # Reduced from 50Gi (only for thumbnails/cache)
  media:
    size: 2Gi      # Reduced from 10Gi (temp files only)
  consume:
    size: 2Gi      # Inbox for new documents
  export:
    size: 2Gi      # Export destination
```

### Nextcloud (Primary Storage)

Nextcloud can use S3 as primary storage backend.

#### Configuration

Add to `values.yaml`:

```yaml
nextcloud:
  configs:
    s3.config.php: |-
      <?php
      $CONFIG = array(
        'objectstore' => [
          'class' => '\\OC\\Files\\ObjectStore\\S3',
          'arguments' => [
            'bucket' => 'nextcloud-data',
            'autocreate' => true,
            'key' => 'nextcloud-user',
            'secret' => getenv('S3_SECRET_KEY'),
            'hostname' => 'minio.default.svc.cluster.local',
            'port' => 9000,
            'use_ssl' => false,
            'region' => 'us-east-1',
            'use_path_style' => true
          ],
        ],
      );

  extraEnv:
    - name: S3_SECRET_KEY
      valueFrom:
        secretKeyRef:
          name: nextcloud-s3-credentials
          key: secret-access-key
```

#### Important Notes

- **Migration**: Moving existing data to S3 requires manual migration
- **Database**: Still uses PostgreSQL for metadata
- **Performance**: Enable Redis for better performance with S3

## SDK Examples

### Python (boto3)

```python
import boto3
from botocore.client import Config

# Configure S3 client
s3_client = boto3.client(
    's3',
    endpoint_url='http://minio.default.svc.cluster.local:9000',
    aws_access_key_id='your-access-key',
    aws_secret_access_key='your-secret-key',
    config=Config(signature_version='s3v4'),
    region_name='us-east-1'
)

# Upload file
s3_client.upload_file('local-file.jpg', 'mybucket', 'remote-file.jpg')

# Download file
s3_client.download_file('mybucket', 'remote-file.jpg', 'downloaded-file.jpg')

# List objects
response = s3_client.list_objects_v2(Bucket='mybucket')
for obj in response.get('Contents', []):
    print(obj['Key'])
```

### Node.js (aws-sdk)

```javascript
const AWS = require('aws-sdk');

// Configure S3
const s3 = new AWS.S3({
  endpoint: 'http://minio.default.svc.cluster.local:9000',
  accessKeyId: 'your-access-key',
  secretAccessKey: 'your-secret-key',
  s3ForcePathStyle: true,
  signatureVersion: 'v4'
});

// Upload file
const uploadParams = {
  Bucket: 'mybucket',
  Key: 'remote-file.jpg',
  Body: fileStream
};
s3.upload(uploadParams, (err, data) => {
  if (err) console.error(err);
  else console.log('Upload success:', data.Location);
});

// Download file
const downloadParams = {
  Bucket: 'mybucket',
  Key: 'remote-file.jpg'
};
s3.getObject(downloadParams, (err, data) => {
  if (err) console.error(err);
  else console.log('Downloaded:', data.Body);
});
```

### Go (minio-go)

```go
package main

import (
    "context"
    "log"
    "github.com/minio/minio-go/v7"
    "github.com/minio/minio-go/v7/pkg/credentials"
)

func main() {
    // Initialize client
    minioClient, err := minio.New("minio.default.svc.cluster.local:9000", &minio.Options{
        Creds:  credentials.NewStaticV4("your-access-key", "your-secret-key", ""),
        Secure: false,
    })
    if err != nil {
        log.Fatal(err)
    }

    // Upload file
    ctx := context.Background()
    _, err = minioClient.FPutObject(ctx, "mybucket", "remote-file.jpg", "local-file.jpg", minio.PutObjectOptions{})
    if err != nil {
        log.Fatal(err)
    }

    log.Println("Upload successful")
}
```

### Java (AWS SDK)

```java
import com.amazonaws.auth.AWSStaticCredentialsProvider;
import com.amazonaws.auth.BasicAWSCredentials;
import com.amazonaws.client.builder.AwsClientBuilder;
import com.amazonaws.services.s3.AmazonS3;
import com.amazonaws.services.s3.AmazonS3ClientBuilder;
import java.io.File;

public class MinIOExample {
    public static void main(String[] args) {
        // Configure S3 client
        BasicAWSCredentials credentials = new BasicAWSCredentials(
            "your-access-key",
            "your-secret-key"
        );

        AmazonS3 s3Client = AmazonS3ClientBuilder
            .standard()
            .withEndpointConfiguration(
                new AwsClientBuilder.EndpointConfiguration(
                    "http://minio.default.svc.cluster.local:9000",
                    "us-east-1"
                )
            )
            .withPathStyleAccessEnabled(true)
            .withCredentials(new AWSStaticCredentialsProvider(credentials))
            .build();

        // Upload file
        s3Client.putObject("mybucket", "remote-file.jpg", new File("local-file.jpg"));
        System.out.println("Upload successful");
    }
}
```

## Security

### Access Control

#### 1. Bucket Policies

Create least-privilege policies:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {"AWS": ["arn:aws:iam:::user/immich-user"]},
      "Action": [
        "s3:GetObject",
        "s3:PutObject",
        "s3:DeleteObject"
      ],
      "Resource": ["arn:aws:s3:::immich-media/*"]
    }
  ]
}
```

Apply policy:

```bash
mc anonymous set-json immich-policy.json myminio/immich-media
```

#### 2. Encryption at Rest

Enable server-side encryption:

```bash
# Using mc
mc encrypt set sse-s3 myminio/immich-media

# Or in application config
export AWS_S3_ENCRYPT=true
```

#### 3. TLS/HTTPS

For production, enable TLS:

```yaml
# MinIO values.yaml
ingress:
  api:
    enabled: true
    annotations:
      cert-manager.io/cluster-issuer: letsencrypt-prod
    hosts:
      - host: s3.example.com
        paths:
          - path: /
            pathType: Prefix
    tls:
      - secretName: minio-api-tls
        hosts:
          - s3.example.com
```

Update application endpoints to use HTTPS:

```yaml
- name: AWS_ENDPOINT
  value: "https://s3.example.com"
- name: AWS_S3_USE_SSL
  value: "true"
```

### Kubernetes Secrets Management

Use external-secrets or sealed-secrets for production:

```yaml
apiVersion: external-secrets.io/v1beta1
kind: ExternalSecret
metadata:
  name: immich-s3-credentials
spec:
  refreshInterval: 1h
  secretStoreRef:
    name: vault-backend
    kind: SecretStore
  target:
    name: immich-s3-credentials
  data:
    - secretKey: access-key-id
      remoteRef:
        key: secret/data/immich/s3
        property: access_key_id
    - secretKey: secret-access-key
      remoteRef:
        key: secret/data/immich/s3
        property: secret_access_key
```

## Troubleshooting

### Connection Issues

**Symptom**: Application cannot connect to MinIO

**Diagnosis**:

```bash
# Test DNS resolution
kubectl run -it --rm debug --image=busybox --restart=Never -- nslookup minio.default.svc.cluster.local

# Test connectivity
kubectl run -it --rm debug --image=curlimages/curl --restart=Never -- \
  curl -v http://minio.default.svc.cluster.local:9000/minio/health/live
```

**Solutions**:
- Verify service name and namespace
- Check NetworkPolicy allows traffic
- Ensure MinIO pods are running: `kubectl get pods -l app.kubernetes.io/name=minio`

### Authentication Errors

**Symptom**: `AccessDenied` or `InvalidAccessKeyId`

**Diagnosis**:

```bash
# Verify credentials
kubectl get secret immich-s3-credentials -o jsonpath='{.data.access-key-id}' | base64 -d
kubectl get secret immich-s3-credentials -o jsonpath='{.data.secret-access-key}' | base64 -d

# Test with mc
mc alias set test http://minio:9000 ACCESS_KEY SECRET_KEY
mc ls test
```

**Solutions**:
- Verify credentials match MinIO user
- Check user has correct policy attached
- Ensure bucket exists

### Slow Performance

**Symptom**: Slow upload/download speeds

**Diagnosis**:

```bash
# Check MinIO metrics
kubectl port-forward svc/minio 9000:9000
curl http://localhost:9000/minio/v2/metrics/cluster | grep minio_s3_requests

# Check network bandwidth
kubectl run -it --rm iperf --image=networkstatic/iperf3 -- iperf3 -c minio.default.svc.cluster.local
```

**Solutions**:
- Use SSD storage class for MinIO PVCs
- Increase MinIO resources (CPU/memory)
- Enable connection pooling in application
- Use distributed mode for better throughput

### Bucket Already Exists Error

**Symptom**: `BucketAlreadyOwnedByYou` or `BucketAlreadyExists`

**Solution**: This is usually harmless if using `autocreate: true`. Disable autocreate if bucket already exists:

```yaml
- name: PAPERLESS_AWS_AUTO_CREATE_BUCKET
  value: "false"
```

### Path Style vs Virtual Hosted Style

**Symptom**: `NoSuchBucket` errors

MinIO uses path-style URLs by default. Ensure applications are configured correctly:

```yaml
# Path style (MinIO default)
AWS_S3_ADDRESSING_STYLE=path
# URL: http://minio:9000/mybucket/object

# Virtual hosted style (AWS default)
AWS_S3_ADDRESSING_STYLE=virtual
# URL: http://mybucket.minio:9000/object
```

For MinIO, always use path style:

```yaml
- name: AWS_S3_USE_PATH_STYLE
  value: "true"
```

## Additional Resources

- [MinIO Chart Documentation](../charts/minio/README.md)
- [MinIO Official Documentation](https://min.io/docs/minio/linux/index.html)
- [AWS S3 API Reference](https://docs.aws.amazon.com/AmazonS3/latest/API/Welcome.html)
- [Immich Documentation](https://immich.app/docs)
- [Paperless-ngx Documentation](https://docs.paperless-ngx.com/)
- [Nextcloud Object Storage](https://docs.nextcloud.com/server/latest/admin_manual/configuration_files/primary_storage.html)

## Contributing

Found an issue or have a suggestion? Please open an issue or pull request in the [sb-helm-charts repository](https://github.com/scriptonbasestar-container/sb-helm-charts).
