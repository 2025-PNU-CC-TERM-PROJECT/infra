#!/bin/bash

set -e  # 에러 시 종료

# 1. Docker 이미지 pull
echo "Pulling Docker images..."
docker pull yeseul01/ocr-api:latest
docker pull yeseul01/inference-service:latest

# 2. Kubernetes 리소스 배포
echo "Applying Kubernetes resources..."
kubectl apply -f ocr-deploy.yaml
kubectl apply -f inference-deploy.yaml
kubectl apply -f ingress.yaml

echo "Deployment complete!"
echo "서비스 경로:"
echo " - /ocr → ocr-api (port 9000)"
echo " - /predict → inference-service (port 8080)"
echo " - /      → inference-service (port 8080)"
