#!/bin/bash

set -e  # 에러 발생 시 종료
set -o pipefail

echo "🚀 KServe를 제외한 구성 요소 설치 시작..."

### 1. 네임스페이스 생성
echo "[1] 네임스페이스 생성 중..."
# KServe 관련 네임스페이스 제외
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Namespace
metadata:
  name: istio-system
---
apiVersion: v1
kind: Namespace
metadata:
  name: knative-serving
---
apiVersion: v1
kind: Namespace
metadata:
  name: knative-eventing
---
apiVersion: v1
kind: Namespace
metadata:
  name: monitoring
---
apiVersion: v1
kind: Namespace
metadata:
  name: ms-frontend
---
apiVersion: v1
kind: Namespace
metadata:
  name: ms-backend
EOF
echo "[1] 네임스페이스 생성 완료."

### 2. Istio 설치
echo "[2] Istio 설치 중..."
helm repo add istio https://istio-release.storage.googleapis.com/charts
helm repo update
# 이미 설치되어 있는지 확인 후 설치
if ! helm list -n istio-system | grep -q "istio-base"; then
  helm install istio-base istio/base -n istio-system
else
  echo "istio-base가 이미 설치되어 있어 건너뜁니다."
fi

if ! helm list -n istio-system | grep -q "istiod"; then
  helm install istiod istio/istiod -n istio-system --wait
else
  echo "istiod가 이미 설치되어 있어 건너뜁니다."
fi

if ! helm list -n istio-system | grep -q "ingressgateway"; then
  helm install ingressgateway istio/gateway -n istio-system
else
  echo "ingressgateway가 이미 설치되어 있어 건너뜁니다."
fi
echo "[2] Istio 설치 완료."
helm ls -n istio-system 

### 2-1. 라벨 추가 (Istio 설치 이후)
echo "[2-1] Istio sidecar injection 활성화 중..."
kubectl label namespace default istio-injection=enabled --overwrite
kubectl label namespace ms-frontend istio-injection=enabled --overwrite
kubectl label namespace ms-backend istio-injection=enabled --overwrite
echo "[2-1] 라벨 추가 완료."

### 3. Knative 설치
echo "[3] Knative Serving 설치 중..."
kubectl apply -f https://github.com/knative/serving/releases/download/knative-v1.18.0/serving-crds.yaml
kubectl apply -f https://github.com/knative/serving/releases/download/knative-v1.18.0/serving-core.yaml
kubectl apply -f https://github.com/knative/net-istio/releases/download/knative-v1.18.0/net-istio.yaml
kubectl patch configmap config-domain \
  -n knative-serving \
  --type merge \
  -p '{"data":{"example.com":""}}'
echo "[3] Knative 설치 완료."

### 4. 모니터링 구성
echo "[4] 모니터링 서비스 설치 중..."
# Jaeger
kubectl apply -f https://raw.githubusercontent.com/istio/istio/release-1.20/samples/addons/jaeger.yaml

# Prometheus
kubectl apply -f https://raw.githubusercontent.com/istio/istio/release-1.20/samples/addons/prometheus.yaml

# Grafana
kubectl apply -f https://raw.githubusercontent.com/istio/istio/release-1.20/samples/addons/grafana.yaml

# Kiali
kubectl apply -f https://raw.githubusercontent.com/istio/istio/release-1.20/samples/addons/kiali.yaml

# 모니터링 도구 Gateway 설정
echo "[4-1] 모니터링 서비스 게이트웨이 설정 중..."
kubectl apply -f kiali-gateway.yaml
kubectl apply -f prometheus-gateway.yaml
kubectl apply -f grafana-gateway.yaml
kubectl apply -f jaeger-gateway.yaml
echo "[4-1] 모니터링 서비스 게이트웨이 설정 완료."

echo "[4] 모니터링 서비스 설치 완료."

### 5. 프론트엔드/백엔드/DB 배포
echo "[5] 애플리케이션 배포 중..."
kubectl apply -f postgres.yaml
kubectl apply -f ksvc-ms-backend.yaml
kubectl apply -f ksvc-ms-frontend.yaml
echo "[5] 애플리케이션 배포 완료."

### 6. 정보 출력
echo "📡 IngressGateway external IP:"
kubectl get svc ingressgateway -n istio-system

echo "📘 참고: /etc/hosts 에 다음과 같이 도메인 매핑이 필요할 수 있습니다."
echo "예: 34.XX.XX.XX ms-frontend.ms-frontend.example.com"
echo "예: 34.XX.XX.XX ms-backend.ms-backend.example.com"
echo "예: 34.XX.XX.XX kiali.monitoring.com"
echo "예: 34.XX.XX.XX prometheus.monitoring.com"
echo "예: 34.XX.XX.XX grafana.monitoring.com"
echo "예: 34.XX.XX.XX jaeger.monitoring.com"

echo "✅ KServe를 제외한 모든 구성 요소 설치 완료!" 