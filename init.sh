#!/bin/bash

# Wait for LocalStack S3 endpoint to be fully operational
echo "Waiting for LocalStack to be ready..."
until aws --endpoint-url=http://localstack:4566 s3 ls; do
  echo "LocalStack not ready yet. Retrying in 2 seconds..."
  sleep 2
done

echo "LocalStack is ready! Proceeding with resource initialization."

# 1. Create the primary mock S3 bucket
echo "Creating S3 bucket 'lakehouse-bucket'..."
aws --endpoint-url=http://localstack:4566 s3 mb s3://lakehouse-bucket

echo "============================================="
echo "Initialization complete!"
echo "S3 Bucket 'lakehouse-bucket' created."
echo "============================================="

# 2. Initialize Unity Catalog Server
echo "Waiting for Unity Catalog server to be ready..."
until curl -s http://unity-catalog-server:8080/api/2.1/unity-catalog/catalogs > /dev/null; do
  echo "Unity Catalog not ready. Retrying in 2 seconds..."
  sleep 2
done

echo "Creating 'unity' catalog and 'default' schema..."
curl -s -X POST http://unity-catalog-server:8080/api/2.1/unity-catalog/catalogs \
  -H 'Content-Type: application/json' \
  -d '{"name": "unity", "comment": "Main catalog"}' > /dev/null

curl -s -X POST http://unity-catalog-server:8080/api/2.1/unity-catalog/schemas \
  -H 'Content-Type: application/json' \
  -d '{"name": "default", "catalog_name": "unity", "comment": "Default schema"}' > /dev/null

echo "Unity Catalog initialization complete!"
