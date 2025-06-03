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
  name: ms-frontend
---
apiVersion: v1
kind: Namespace
metadata:
  name: ms-backend
---
apiVersion: v1
kind: Namespace
metadata:
  name: ms-models
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
kubectl label namespace ms-models istio-injection=enabled --overwrite
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

### 4-2. Knative initContainers 기능 활성화
echo "[4-2] Knative initContainers 기능 활성화 중..."
kubectl patch configmap config-features -n knative-serving --type merge -p '{"data":{"kubernetes.podspec-init-containers":"enabled"}}'
echo "[4-2] Knative initContainers 기능 활성화 완료."

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
echo "[6] 백앤드 및 DB 배포 중..."
kubectl apply -f postgres.yaml

# AI 서비스 URL을 동적으로 설정하여 백엔드 서비스 배포
echo "[6-0] AI 서비스 URL을 동적으로 설정하여 백엔드 배포..."
cat <<EOF | kubectl apply -f -
apiVersion: serving.knative.dev/v1
kind: Service
metadata:
  name: ms-backend
  namespace: ms-backend
spec:
  template:
    metadata:
      annotations:
        autoscaling.knative.dev/minScale: "0" # serverless 동작을 위해 0으로 설정
        autoscaling.knative.dev/maxScale: "5" # 최대 5개 Pod까지 확장 가능
        # 자동 스케일링 설정
        autoscaling.knative.dev/target: "50" # 트래픽 부하 기준점 (요청 개수 기준)
    spec:
      initContainers:
        - name: wait-for-database
          image: busybox:1.35
          command:
            [
              "sh",
              "-c",
              "until nc -z -w 2 database 5432; do echo 'Waiting for database...'; sleep 2; done",
            ]
      containers:
        - image: xxhyeok/ms-backend:latest
          ports:
            - containerPort: 8080
          env:
            - name: SPRING_PROFILE
              value: prod
            - name: DATASOURCE_URL
              value: jdbc:postgresql://database:5432/cc-term
            - name: DATASOURCE_USERNAME
              value: user
            - name: DATASOURCE_PASSWORD
              value: "1234"
EOF

### 6-1. 프론트엔드 .env.production 생성
echo "[6-1] 프론트엔드 .env.production 생성..."
cat <<EOF > ../ms-frontend/.env.production
NEXT_PUBLIC_API_URL=http://ms-backend.ms-backend.${MAGIC_DOMAIN}
NEXT_PUBLIC_GRAFANA_URL=http://grafana.${MAGIC_DOMAIN}
NEXT_PUBLIC_KIALI_URL=http://kiali.${MAGIC_DOMAIN}
EOF

### 6-2. Next.js 빌드 및 Docker 이미지 빌드/푸시
echo "[6-2] Next.js 프론트엔드 빌드 및 이미지 생성..."
cd ../ms-frontend
npm install
npm run build

echo "[6-3] Docker 이미지 빌드 및 푸시..."
docker build --platform linux/amd64 -t xxhyeok/ms-frontend:latest .
docker push xxhyeok/ms-frontend:latest
cd ../infra

### 6-4. 프론트엔드 Knative 서비스 배포
echo "[6-4] Knative 프론트엔드 서비스 배포..."
kubectl apply -f ksvc-ms-frontend.yaml
echo "[6] 애플리케이션 배포 완료."

### 6-5. cert-manager 설치
echo "[6-5] cert-manager 설치 중..."
kubectl apply -f https://github.com/cert-manager/cert-manager/releases/download/v1.17.2/cert-manager.yaml

echo "[6-5-1] cert-manager CRDs 준비 대기 중..."
# cert-manager CRDs가 생성될 때까지 대기
kubectl wait --for condition=established --timeout=60s crd/certificates.cert-manager.io
kubectl wait --for condition=established --timeout=60s crd/certificaterequests.cert-manager.io
kubectl wait --for condition=established --timeout=60s crd/issuers.cert-manager.io
kubectl wait --for condition=established --timeout=60s crd/clusterissuers.cert-manager.io

echo "[6-5-2] cert-manager pods 준비 대기 중..."
# cert-manager controller pods가 준비될 때까지 대기
kubectl wait --for=condition=Ready pod -l app=cert-manager -n cert-manager --timeout=300s
kubectl wait --for=condition=Ready pod -l app=cainjector -n cert-manager --timeout=300s
kubectl wait --for=condition=Ready pod -l app=webhook -n cert-manager --timeout=300s

echo "[6-5] cert-manager 설치 및 준비 완료."


### 7. KServe 설치
echo "[7] KServe 설치 중..."
kubectl apply --server-side -f https://github.com/kserve/kserve/releases/download/v0.15.0/kserve.yaml
kubectl apply --server-side -f https://github.com/kserve/kserve/releases/download/v0.15.0/kserve-cluster-resources.yaml

echo "[7] KServe 설치 완료."

### ai pod 배포
echo "[7-1] KServe AI 모델 배포 중..."
kubectl apply -f Kserve-ai-image-serving.yaml
kubectl apply -f Kserve-ai-text-serving.yaml

echo "[7-2] AI 서비스가 준비될 때까지 대기 중..."
# AI 서비스가 준비될 때까지 대기
kubectl wait --for=condition=Ready inferenceservice/ai-image-serving -n ms-models --timeout=300s
kubectl wait --for=condition=Ready inferenceservice/ai-text-serving -n ms-models --timeout=300s

echo "[7-3] KServe AI 모델 배포 완료."

### 8. 정보 출력
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
echo "🤖 AI 서비스 URL들:"
echo "  • AI Image:   http://ai-image-serving.ms-models.${MAGIC_DOMAIN}/v1/models/mobilenet:predict"
echo "  • AI Text:    http://ai-text-serving.ms-models.${MAGIC_DOMAIN}/v1/models/kobart-summary:predict"
echo ""
echo "✅ 모든 구성 요소 설치 완료!"