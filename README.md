# infra 구성 파일 및 자동 스크립트
## 프로젝트 개요

이 프로젝트는 Istio, Knative, KServe 및 모니터링 도구(Prometheus, Grafana, Kiali 등)를 포함한 클러스터 전체 인프라 구성과 마이크로서비스 배포를 자동화하는 스크립트를 제공합니다.

## 구성 파일 

| 파일명                     | 설명                              |
| ----------------------- | ------------------------------------ |
| `setup-all.sh`          | 전체 클러스터 구성 자동화 스크립트                  |
| `postgres.yaml`         | PostgreSQL 데이터베이스 배포 구성              |
| `ksvc-ms-backend.yaml`  | Knative 기반 백엔드 서비스 정의                |
| `ksvc-ms-frontend.yaml` | Knative 기반 프론트엔드 서비스 정의              |
| `kiali-gateway.yaml`    | Kiali UI를 외부에 노출시키는 Istio Gateway 설정 |
| `README.md`             | 프로젝트 설명 문서                           |

## 실행 방법

- 사전 요구 사항

1. kubectl, helm, gcloud CLI 설치

2. GKE 클러스터 또는 로컬 쿠버네티스 환경 구성

3. 컨테이너 이미지(프론트/백엔드) 사전 빌드 및 퍼블릭 레지스트리에 업로드

- 스크립트 실행
'''
chmod +x setup-all.sh
./setup-all.sh
'''

- host 파일에 도메인 추가
'''
34.xxx.xxx.xxx  kiali.monitoring.com
34.xxx.xxx.xxx  ms-frontend.ms-frontend.example.com
34.xxx.xxx.xxx  ms-backend.ms-backend.example.com
'''

## 결과물 예시

프론트엔드 접근: http://ms-frontend.ms-frontend.example.com

백엔드 접근: http://ms-backend.ms-backend.example.com

Kiali UI: http://kiali.monitoring.com

