#!/bin/bash

set -e  # 에러 발생 시 종료
set -o pipefail

echo "🚀 Starting full cluster setup..."

### 1. 네임스페이스 생성
echo "[1] Creating namespaces..."
kubectl create namespace istio-system || true
kubectl create namespace knative-serving || true
kubectl create namespace knative-eventing || true
kubectl create namespace kserve || true
kubectl create namespace monitoring || true
kubectl create namespace ms-frontend || true
kubectl create namespace ms-backend || true
kubectl create namespace ms-models || true

### 2. Istio 설치
echo "[2] Installing Istio..."
helm repo add istio https://istio-release.storage.googleapis.com/charts
helm repo update
helm install istio-base istio/base -n istio-system
helm install istiod istio/istiod -n istio-system --wait
helm install ingressgateway istio/gateway -n istio-system
echo "[2] Istio installed."
helm ls -n istio-system 

### 2-1. 라벨 추가 (Istio 설치 이후)
echo "[2-1] Enabling Istio sidecar injection..."
kubectl label namespace default istio-injection=enabled --overwrite
kubectl label namespace ms-frontend istio-injection=enabled --overwrite
kubectl label namespace ms-backend istio-injection=enabled --overwrite
kubectl label namespace ms-models istio-injection=enabled --overwrite

### 3. knative 설치
echo "[3] Installing Knative Serving..."
kubectl apply -f https://github.com/knative/serving/releases/download/knative-v1.18.0/serving-crds.yaml
kubectl apply -f https://github.com/knative/serving/releases/download/knative-v1.18.0/serving-core.yaml
kubectl apply -f https://github.com/knative/net-istio/releases/download/knative-v1.18.0/net-istio.yaml
kubectl patch configmap config-domain \
  -n knative-serving \
  --type merge \
  -p '{"data":{"example.com":""}}'
echo "[3] Knative installed."


### 4. Kserve 설치
echo "[4] Installing Kserve..."
kubectl apply -f https://github.com/jetstack/cert-manager/releases/download/v1.11.0/cert-manager.yaml
kubectl apply --server-side -f https://github.com/kserve/kserve/releases/download/v0.15.0/kserve.yaml
kubectl apply --server-side -f https://github.com/kserve/kserve/releases/download/v0.15.0/kserve-cluster-resources.yaml

### 5. 모니터링 구성
echo "[5] Installing monitoring services..."
#jaeger
kubectl apply -f https://raw.githubusercontent.com/istio/istio/release-1.20/samples/addons/jaeger.yaml

#prometheus
kubectl apply -f https://raw.githubusercontent.com/istio/istio/release-1.20/samples/addons/prometheus.yaml

#Grafana
kubectl apply -f https://raw.githubusercontent.com/istio/istio/release-1.20/samples/addons/grafana.yaml

#Kiali
kubectl apply -f https://raw.githubusercontent.com/istio/istio/release-1.20/samples/addons/kiali.yaml

kubectl apply -f kiali-gateway.yaml

echo "[5] monitoring services installed."


###6. 프론트엔드/백엔드/DB 배포
echo "[6] Deploying frontend, backend and database..."
kubectl apply -f postgres.yaml
kubectl apply -f ksvc-ms-backend.yaml
kubectl apply -f ksvc-ms-frontend.yaml

### 7. 정보 출력
echo "📡 IngressGateway external IP:"
kubectl get svc ingressgateway -n istio-system

echo "📘 참고: /etc/hosts 에 다음과 같이 도메인 매핑이 필요할 수 있습니다."
echo "예: 34.XX.XX.XX ms-frontend.ms-frontend.example.com"

echo "✅ All components installed successfully!








