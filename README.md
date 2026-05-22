# infra 구성 파일 및 자동 스크립트
## 프로젝트 개요

이 프로젝트는 Istio, Knative, KServe 및 모니터링 도구(Prometheus, Grafana, Kiali 등)를 포함한 클러스터 전체 인프라 구성과 마이크로서비스 배포를 자동화하는 스크립트를 제공합니다.

## 🧩 구성 요소

- **Istio**: 서비스 메시 관리 및 트래픽 제어
- **Knative Serving**: 서버리스 백엔드/API Gateway 애플리케이션 배포
- **KServe**: AI 모델 배포 및 예측 처리
- **Monitoring Stack**: Kiali, Grafana, Prometheus, Jaeger 기반 서비스 관찰성
- **PostgreSQL**: 백엔드 데이터베이스
- **API Gateway**: 외부 프론트엔드에서 내부 백엔드로 들어오는 API 요청 중계
- **Next.js 프론트엔드**: Kubernetes 클러스터 바깥에서 별도 배포

## 📦 설치 스크립트 실행

```bash
chmod +x setup.sh
export DOCKER_REGISTRY=${your-docker-name}
./setup.sh
```
> ✅ 이 스크립트는 다음 항목을 자동으로 설치하고 구성합니다:
>
> - 네임스페이스 생성  
> - Istio + ingress gateway  
> - Knative Serving + net-istio + 도메인 설정  
> - 모니터링 도구 설치 및 라우팅 설정  
> - 백엔드/API Gateway 빌드 및 배포  
> - cert-manager 설치  
> - KServe 기반 AI 모델 서빙

로컬 Minikube에서 레지스트리 push 없이 실행하려면 PowerShell에서 다음 스크립트를 사용합니다:

```powershell
.\setup-local-minikube.ps1
```

## 🌐 설치 후 접근 가능한 주요 URL

스크립트 실행 후 아래와 같은 Magic DNS 도메인이 출력됩니다:

### 📡 Ingress Gateway

| 서비스       | 주소 |
|--------------|------|
| API Gateway  | `http://api.<EXTERNAL-IP>.sslip.io` |
| Kiali        | `http://kiali.<EXTERNAL-IP>.sslip.io`  
| Prometheus   | `http://prometheus.<EXTERNAL-IP>.sslip.io`  
| Grafana      | `http://grafana.<EXTERNAL-IP>.sslip.io`  
| Jaeger       | `http://jaeger.<EXTERNAL-IP>.sslip.io`  

### 🧭 애플리케이션

| 서비스       | 주소 |
|--------------|------|
| Frontend     | 클러스터 바깥(Vercel, S3 + CloudFront, 별도 Nginx 등)에 배포하고 `NEXT_PUBLIC_API_URL`을 API Gateway 주소로 설정 |
| Backend      | `http://ms-backend.ms-backend.<EXTERNAL-IP>.sslip.io`  

### 🤖 AI 모델 서빙 (KServe)

| 모델         | Predict URL |
|--------------|-------------|
| Image Model  | `http://ai-image-serving.ms-models.<EXTERNAL-IP>.sslip.io/v1/models/mobilenet:predict`  
| Text Model   | `http://ai-text-serving.ms-models.<EXTERNAL-IP>.sslip.io/v1/models/kobart-summary:predict`  

---

## ⚙️ 사전 요구사항

- Kubernetes 클러스터 (GKE, Minikube 등)
- Helm CLI
- Docker CLI 및 Hub 로그인
- `kubectl` 설정 완료
- 외부 접근이 가능한 LoadBalancer 타입 서비스가 지원되는 클러스터

---

## 📝 참고

- Magic DNS: `sslip.io`를 사용하여 External IP 기반 서브도메인을 자동 생성합니다.
- `.env.production` 파일은 자동 생성되며, API URL 및 Grafana/Kiali 접근 주소를 포함합니다.
- AI 모델은 KServe로 서빙되며, 각 서비스 준비 완료까지 대기 로직이 포함되어 있습니다.

---
