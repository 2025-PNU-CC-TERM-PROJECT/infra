# Local Runtime

This directory provides a local runtime that avoids requiring Istio, Knative, and KServe during everyday frontend/backend development.

## Run

```bash
docker compose -f infra/local/docker-compose.yml up --build
```

## Services

| Service | URL |
| --- | --- |
| Frontend | http://localhost:3000 |
| API Gateway | http://localhost:8088 |
| Backend | http://localhost:8080 |
| Image model mock | http://localhost:9001 |
| Text model mock | http://localhost:9002 |
| PostgreSQL | localhost:5432 |

## Why Mock Models Exist

The production model path uses KServe. For local development, mock model servers implement the same response shapes expected by `ms-backend`, so UI and backend flows can be developed without a Kubernetes cluster.
