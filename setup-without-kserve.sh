#!/bin/bash

set -e  # 에러 발생 시 종료
set -o pipefail

echo "🚀 KServe를 제외한 구성 요소 설치 시작..."

### 1. 네임스페이스 생성
echo "[1] 네임스페이스 생성 중..."
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

### 2-1. 라벨 추가 (Istio 설치 이후)
echo "[2-1] Istio sidecar injection 활성화 중..."
kubectl label namespace default istio-injection=enabled --overwrite
kubectl label namespace ms-frontend istio-injection=enabled --overwrite
kubectl label namespace ms-backend istio-injection=enabled --overwrite
echo "[2-1] 라벨 추가 완료."

### 3. External IP 확인 및 Magic DNS 도메인 설정
echo "[3] IngressGateway External IP 확인 중..."
# External IP가 할당될 때까지 대기
echo "External IP 할당 대기 중..."
while true; do
  EXTERNAL_IP=$(kubectl get svc ingressgateway -n istio-system -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || echo "")
  if [[ -n "$EXTERNAL_IP" && "$EXTERNAL_IP" != "null" ]]; then
    echo "External IP 확인: $EXTERNAL_IP"
    break
  fi
  echo "External IP 할당 대기 중... (30초 후 재시도)"
  sleep 30
done

# Magic DNS 도메인 설정 (sslip.io 사용)
MAGIC_DOMAIN="${EXTERNAL_IP}.sslip.io"
echo "Magic DNS 도메인: $MAGIC_DOMAIN"

### 4. Knative 설치 및 도메인 설정
echo "[4] Knative Serving 설치 중..."
kubectl apply -f https://github.com/knative/serving/releases/download/knative-v1.18.0/serving-crds.yaml
kubectl apply -f https://github.com/knative/serving/releases/download/knative-v1.18.0/serving-core.yaml
kubectl apply -f https://github.com/knative/net-istio/releases/download/knative-v1.18.0/net-istio.yaml

# Knative에 Magic DNS 도메인 설정
echo "[4-1] Knative 도메인 설정 중..."
kubectl patch configmap config-domain \
  -n knative-serving \
  --type merge \
  -p "{\"data\":{\"${MAGIC_DOMAIN}\":\"\"}}"
echo "[4] Knative 설치 완료."

### 5. 모니터링 구성
echo "[5] 모니터링 서비스 설치 중..."
kubectl apply -f https://raw.githubusercontent.com/istio/istio/release-1.20/samples/addons/jaeger.yaml
kubectl apply -f https://raw.githubusercontent.com/istio/istio/release-1.20/samples/addons/prometheus.yaml
kubectl apply -f https://raw.githubusercontent.com/istio/istio/release-1.20/samples/addons/grafana.yaml
kubectl apply -f https://raw.githubusercontent.com/istio/istio/release-1.20/samples/addons/kiali.yaml

### 5-1. 모니터링 도구 Gateway 설정 (Magic DNS 사용)
echo "[5-1] 모니터링 서비스 게이트웨이 설정 중..."

# Kiali Gateway
cat <<EOF | kubectl apply -f -
apiVersion: networking.istio.io/v1alpha3
kind: Gateway
metadata:
  name: kiali-gateway
  namespace: istio-system
spec:
  selector:
    istio: ingressgateway
  servers:
  - port:
      number: 80
      name: http
      protocol: HTTP
    hosts:
    - kiali.${MAGIC_DOMAIN}
---
apiVersion: networking.istio.io/v1alpha3
kind: VirtualService
metadata:
  name: kiali-vs
  namespace: istio-system
spec:
  hosts:
  - kiali.${MAGIC_DOMAIN}
  gateways:
  - kiali-gateway
  http:
  - route:
    - destination:
        host: kiali
        port:
          number: 20001
EOF

# Prometheus Gateway
cat <<EOF | kubectl apply -f -
apiVersion: networking.istio.io/v1alpha3
kind: Gateway
metadata:
  name: prometheus-gateway
  namespace: istio-system
spec:
  selector:
    istio: ingressgateway
  servers:
  - port:
      number: 80
      name: http
      protocol: HTTP
    hosts:
    - prometheus.${MAGIC_DOMAIN}
---
apiVersion: networking.istio.io/v1alpha3
kind: VirtualService
metadata:
  name: prometheus-vs
  namespace: istio-system
spec:
  hosts:
  - prometheus.${MAGIC_DOMAIN}
  gateways:
  - prometheus-gateway
  http:
  - route:
    - destination:
        host: prometheus
        port:
          number: 9090
EOF

# Grafana Gateway
cat <<EOF | kubectl apply -f -
apiVersion: networking.istio.io/v1alpha3
kind: Gateway
metadata:
  name: grafana-gateway
  namespace: istio-system
spec:
  selector:
    istio: ingressgateway
  servers:
  - port:
      number: 80
      name: http
      protocol: HTTP
    hosts:
    - grafana.${MAGIC_DOMAIN}
---
apiVersion: networking.istio.io/v1alpha3
kind: VirtualService
metadata:
  name: grafana-vs
  namespace: istio-system
spec:
  hosts:
  - grafana.${MAGIC_DOMAIN}
  gateways:
  - grafana-gateway
  http:
  - route:
    - destination:
        host: grafana
        port:
          number: 3000
EOF

# Jaeger Gateway
cat <<EOF | kubectl apply -f -
apiVersion: networking.istio.io/v1alpha3
kind: Gateway
metadata:
  name: jaeger-gateway
  namespace: istio-system
spec:
  selector:
    istio: ingressgateway
  servers:
  - port:
      number: 80
      name: http
      protocol: HTTP
    hosts:
    - jaeger.${MAGIC_DOMAIN}
---
apiVersion: networking.istio.io/v1alpha3
kind: VirtualService
metadata:
  name: jaeger-vs
  namespace: istio-system
spec:
  hosts:
  - jaeger.${MAGIC_DOMAIN}
  gateways:
  - jaeger-gateway
  http:
  - route:
    - destination:
        host: tracing
        port:
          number: 80
EOF

echo "[5-1] 모니터링 서비스 게이트웨이 설정 완료."
echo "[5] 모니터링 서비스 설치 완료."

### 6. 프론트엔드/백엔드/DB 배포
echo "[6] 애플리케이션 배포 중..."
kubectl apply -f postgres.yaml
kubectl apply -f ksvc-ms-backend.yaml
kubectl apply -f ksvc-ms-frontend.yaml
echo "[6] 애플리케이션 배포 완료."

### 7. 정보 출력
echo ""
echo "🎉 설치 완료!"
echo "📡 IngressGateway External IP: $EXTERNAL_IP"
echo "🌐 Magic DNS 도메인: $MAGIC_DOMAIN"
echo ""
echo "🔗 접근 가능한 URL들:"
echo "  • Kiali:      http://kiali.${MAGIC_DOMAIN}"
echo "  • Prometheus: http://prometheus.${MAGIC_DOMAIN}"
echo "  • Grafana:    http://grafana.${MAGIC_DOMAIN}"
echo "  • Jaeger:     http://jaeger.${MAGIC_DOMAIN}"
echo ""
echo "  • Frontend:   http://ms-frontend.ms-frontend.${MAGIC_DOMAIN}"
echo "  • Backend:    http://ms-backend.ms-backend.${MAGIC_DOMAIN}"
echo ""
echo "✅ 모든 구성 요소 설치 완료!"