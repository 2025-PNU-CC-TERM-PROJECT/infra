#!/bin/bash

set -e  # 에러 발생 시 종료
set -o pipefail

echo "🧹 Magic DNS 구성을 포함한 구성요소 삭제 (KServe 제외)..."

### 1. 애플리케이션 리소스 삭제
echo "[1] 애플리케이션 리소스 삭제 중..."
kubectl delete -f apps/api-gateway-knative.yaml --ignore-not-found
kubectl delete -f apps/api-gateway.yaml --ignore-not-found
kubectl delete -f ksvc-ms-backend.yaml --ignore-not-found
kubectl delete -f postgres.yaml --ignore-not-found
echo "[1] 애플리케이션 리소스 삭제 완료."

### 2. Magic DNS로 생성된 게이트웨이 삭제
echo "[2] Magic DNS 게이트웨이 삭제 중..."
kubectl delete gateway kiali-gateway -n istio-system --ignore-not-found
kubectl delete gateway prometheus-gateway -n istio-system --ignore-not-found
kubectl delete gateway grafana-gateway -n istio-system --ignore-not-found
kubectl delete gateway jaeger-gateway -n istio-system --ignore-not-found

kubectl delete virtualservice kiali-vs -n istio-system --ignore-not-found
kubectl delete virtualservice prometheus-vs -n istio-system --ignore-not-found
kubectl delete virtualservice grafana-vs -n istio-system --ignore-not-found
kubectl delete virtualservice jaeger-vs -n istio-system --ignore-not-found
echo "[2] Magic DNS 게이트웨이 삭제 완료."

### 3. 모니터링 도구 삭제
echo "[3] 모니터링 도구 삭제 중..."
kubectl delete -f https://raw.githubusercontent.com/istio/istio/release-1.20/samples/addons/kiali.yaml --ignore-not-found
kubectl delete -f https://raw.githubusercontent.com/istio/istio/release-1.20/samples/addons/grafana.yaml --ignore-not-found
kubectl delete -f https://raw.githubusercontent.com/istio/istio/release-1.20/samples/addons/prometheus.yaml --ignore-not-found
kubectl delete -f https://raw.githubusercontent.com/istio/istio/release-1.20/samples/addons/jaeger.yaml --ignore-not-found
echo "[3] 모니터링 도구 삭제 완료."

### 4. Knative 삭제
echo "[4] Knative 삭제 중..."
kubectl delete -f https://github.com/knative/net-istio/releases/download/knative-v1.18.0/net-istio.yaml --ignore-not-found
kubectl delete -f https://github.com/knative/serving/releases/download/knative-v1.18.0/serving-core.yaml --ignore-not-found
kubectl delete -f https://github.com/knative/serving/releases/download/knative-v1.18.0/serving-crds.yaml --ignore-not-found
echo "[4] Knative 삭제 완료."

### 5. Istio 삭제
echo "[5] Istio 삭제 중..."
helm uninstall ingressgateway -n istio-system || true
helm uninstall istiod -n istio-system || true
helm uninstall istio-base -n istio-system || true
echo "[5] Istio 삭제 완료."

### 6. 라벨 제거
echo "[6] 네임스페이스 라벨 제거 중..."
kubectl label namespace default istio-injection- || true
kubectl label namespace ms-gateway istio-injection- || true
kubectl label namespace ms-backend istio-injection- || true
echo "[6] 네임스페이스 라벨 제거 완료."

### 7. 네임스페이스 삭제
echo "[7] 네임스페이스 삭제 중..."
kubectl delete namespace ms-gateway --ignore-not-found --wait=false || true
kubectl delete namespace ms-backend --ignore-not-found --wait=false || true
kubectl delete namespace monitoring --ignore-not-found --wait=false || true
kubectl delete namespace knative-serving --ignore-not-found --wait=false || true
kubectl delete namespace knative-eventing --ignore-not-found --wait=false || true
kubectl delete namespace istio-system --ignore-not-found --wait=false || true
echo "[7] 네임스페이스 삭제 완료."

echo "✅ Magic DNS 구성을 포함한 구성요소 삭제 완료 (KServe 제외)!" 
