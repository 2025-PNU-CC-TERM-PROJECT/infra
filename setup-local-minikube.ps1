param(
    [string]$FrontendOrigin = "http://localhost:3000",
    [string]$DockerRegistry = "xxhyeok",
    [int]$IngressLocalPort = 8080,
    [switch]$UseLocalImages = $true,
    [switch]$SkipMonitoring,
    [switch]$SkipKServe
)

$ErrorActionPreference = "Stop"

$InfraDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$RepoRoot = Resolve-Path (Join-Path $InfraDir "..")

$FallbackPathEntries = @(
    "C:\minikube",
    "C:\Users\$env:USERNAME\AppData\Local\Microsoft\WinGet\Packages\Helm.Helm_Microsoft.Winget.Source_8wekyb3d8bbwe\windows-amd64"
)

foreach ($entry in $FallbackPathEntries) {
    if ((Test-Path $entry) -and (($env:Path -split ";") -notcontains $entry)) {
        $env:Path = "$entry;$env:Path"
    }
}

function Invoke-Step {
    param(
        [string]$Message,
        [scriptblock]$Action
    )

    Write-Host ""
    Write-Host "==> $Message" -ForegroundColor Cyan
    & $Action
}

function Assert-Command {
    param([string]$Name)

    if (-not (Get-Command $Name -ErrorAction SilentlyContinue)) {
        throw "$Name command was not found. Install it, make sure it is on PATH, then run this script again."
    }
}

function Apply-Yaml {
    param([string]$Yaml)

    $tempFile = New-TemporaryFile
    try {
        Set-Content -LiteralPath $tempFile -Value $Yaml -Encoding utf8
        kubectl apply -f $tempFile
    }
    finally {
        Remove-Item -LiteralPath $tempFile -Force -ErrorAction SilentlyContinue
    }
}

function Wait-For-IngressGatewayService {
    Write-Host "Waiting for ingressgateway Service..."

    for ($i = 0; $i -lt 30; $i++) {
        $svc = kubectl get svc ingressgateway -n istio-system --ignore-not-found 2>$null
        if (-not [string]::IsNullOrWhiteSpace($svc)) {
            break
        }

        Write-Host "ingressgateway Service is not ready yet. Retrying in 5 seconds..."
        Start-Sleep -Seconds 5
    }

    $svc = kubectl get svc ingressgateway -n istio-system --ignore-not-found 2>$null
    if ([string]::IsNullOrWhiteSpace($svc)) {
        throw "ingressgateway Service was not created. Check 'helm list -n istio-system' and Istio gateway installation logs."
    }
}

function Start-IngressPortForward {
    param([int]$LocalPort)

    $existing = Get-CimInstance Win32_Process |
        Where-Object {
            $_.CommandLine -match "kubectl" -and
            $_.CommandLine -match "port-forward" -and
            $_.CommandLine -match "ingressgateway" -and
            $_.CommandLine -match "$LocalPort`:80"
        }

    if ($existing) {
        Write-Host "IngressGateway port-forward is already running on localhost:$LocalPort"
        return
    }

    Write-Host "Starting port-forward watchdog: localhost:$LocalPort -> svc/ingressgateway:80"
    $loopCmd = "while (`$true) { kubectl port-forward -n istio-system svc/ingressgateway ${LocalPort}:80; Start-Sleep -Seconds 2 }"
    Start-Process powershell -ArgumentList @("-NoExit", "-Command", $loopCmd) -WindowStyle Minimized

    Start-Sleep -Seconds 3
}

Assert-Command kubectl
Assert-Command minikube
Assert-Command helm
Assert-Command docker

Invoke-Step "Check minikube and kubectl connectivity" {
    minikube status
    kubectl config use-context minikube
    kubectl get nodes
}

if ($UseLocalImages) {
    $BackendImage = "ko.local/ms-backend:local"
    $GatewayImage = "ko.local/ms-api-gateway:local"
    $ImagePullPolicy = "IfNotPresent"
}
else {
    $BackendImage = "$DockerRegistry/ms-backend:latest"
    $GatewayImage = "$DockerRegistry/ms-api-gateway:latest"
    $ImagePullPolicy = "IfNotPresent"
}

Invoke-Step "Create namespaces" {
    Apply-Yaml @"
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
  name: ms-backend
---
apiVersion: v1
kind: Namespace
metadata:
  name: ms-gateway
  labels:
    istio-injection: enabled
---
apiVersion: v1
kind: Namespace
metadata:
  name: ms-models
"@
}

Invoke-Step "Install Istio" {
    helm repo add istio https://istio-release.storage.googleapis.com/charts
    helm repo update

    $helmList = helm list -n istio-system

    if ($helmList -notmatch "istio-base") {
        helm upgrade --install istio-base base --repo https://istio-release.storage.googleapis.com/charts -n istio-system
    }

    $helmList = helm list -n istio-system
    if ($helmList -notmatch "istiod") {
        helm upgrade --install istiod istiod --repo https://istio-release.storage.googleapis.com/charts -n istio-system --wait
    }

    $helmList = helm list -n istio-system
    if ($helmList -notmatch "ingressgateway") {
        helm upgrade --install ingressgateway gateway --repo https://istio-release.storage.googleapis.com/charts -n istio-system
    }

    kubectl label namespace ms-gateway istio-injection=enabled --overwrite
    kubectl label namespace ms-backend istio-injection=enabled --overwrite
    kubectl label namespace ms-models istio-injection=enabled --overwrite
}

$ApiBaseUrl = "http://localhost:$IngressLocalPort"
$ParsedApiBaseUrl = [System.Uri]$ApiBaseUrl
$ApiDomain = $ParsedApiBaseUrl.Host
$ObservabilityBaseHost = $ParsedApiBaseUrl.Host
$ObservabilityPort = if ($ParsedApiBaseUrl.IsDefaultPort) { "" } else { ":$($ParsedApiBaseUrl.Port)" }

Write-Host ""
Write-Host "API base URL: $ApiBaseUrl" -ForegroundColor Green
Write-Host "Ingress access mode: kubectl port-forward" -ForegroundColor Green
Write-Host "Allowed external frontend origin: $FrontendOrigin" -ForegroundColor Green
Write-Host "Use local images: $UseLocalImages" -ForegroundColor Green

Invoke-Step "Install Knative Serving" {
    kubectl apply -f https://github.com/knative/serving/releases/download/knative-v1.18.0/serving-crds.yaml
    kubectl apply -f https://github.com/knative/serving/releases/download/knative-v1.18.0/serving-core.yaml
    kubectl apply -f https://github.com/knative/net-istio/releases/download/knative-v1.18.0/net-istio.yaml

    kubectl patch configmap config-domain `
        -n knative-serving `
        --type merge `
        -p "{`"data`":{`"example.com`":`"`"}}"

    kubectl patch configmap config-features `
        -n knative-serving `
        --type merge `
        -p "{`"data`":{`"kubernetes.podspec-init-containers`":`"enabled`"}}"

    if ($UseLocalImages) {
        kubectl patch configmap config-deployment `
            -n knative-serving `
            --type merge `
            -p "{`"data`":{`"registriesSkippingTagResolving`":`"ko.local,dev.local,kind.local,localhost`"}}"
    }
}

if (-not $SkipMonitoring) {
    Invoke-Step "Install observability tools and Gateway routes" {
        kubectl apply -f https://raw.githubusercontent.com/istio/istio/release-1.20/samples/addons/jaeger.yaml
        kubectl apply -f https://raw.githubusercontent.com/istio/istio/release-1.20/samples/addons/prometheus.yaml
        kubectl apply -f https://raw.githubusercontent.com/istio/istio/release-1.20/samples/addons/grafana.yaml
        kubectl apply -f https://raw.githubusercontent.com/istio/istio/release-1.20/samples/addons/kiali.yaml

        Apply-Yaml @"
apiVersion: networking.istio.io/v1beta1
kind: Gateway
metadata:
  name: observability-gateway
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
        - "*"
---
apiVersion: networking.istio.io/v1beta1
kind: VirtualService
metadata:
  name: observability-vs
  namespace: istio-system
spec:
  hosts:
    - "*"
  gateways:
    - observability-gateway
  http:
    - match:
        - authority:
            prefix: kiali.
      route:
        - destination:
            host: kiali
            port:
              number: 20001
    - match:
        - authority:
            prefix: prometheus.
      route:
        - destination:
            host: prometheus
            port:
              number: 9090
    - match:
        - authority:
            prefix: grafana.
      route:
        - destination:
            host: grafana
            port:
              number: 3000
    - match:
        - authority:
            prefix: jaeger.
      route:
        - destination:
            host: tracing
            port:
              number: 80
"@
    }
}

Invoke-Step "Build local images and load them into minikube" {
    if ($UseLocalImages) {
        docker build -t $BackendImage (Join-Path $RepoRoot "ms-backend")
        docker build -t $GatewayImage (Join-Path $RepoRoot "api-gateway")
        minikube image load $BackendImage
        minikube image load $GatewayImage
    }
    else {
        docker build -t $GatewayImage (Join-Path $RepoRoot "api-gateway")
        docker push $GatewayImage
    }
}

Invoke-Step "Deploy PostgreSQL" {
    kubectl apply -f (Join-Path $InfraDir "postgres.yaml")
}

Invoke-Step "Deploy backend Knative Service" {
    Apply-Yaml @"
apiVersion: serving.knative.dev/v1
kind: Service
metadata:
  name: ms-backend
  namespace: ms-backend
spec:
  template:
    metadata:
      annotations:
        autoscaling.knative.dev/minScale: "1"
        autoscaling.knative.dev/maxScale: "5"
        autoscaling.knative.dev/target: "50"
    spec:
      initContainers:
        - name: wait-for-database
          image: busybox:1.35
          command:
            - sh
            - -c
            - until nc -z -w 2 database 5432; do echo 'Waiting for database...'; sleep 2; done
      containers:
        - image: $BackendImage
          imagePullPolicy: $ImagePullPolicy
          ports:
            - containerPort: 8080
          env:
            - name: SPRING_PROFILES_ACTIVE
              value: prod
            - name: SPRING_DATASOURCE_URL
              value: jdbc:postgresql://database:5432/cc-term
            - name: SPRING_DATASOURCE_USERNAME
              value: user
            - name: SPRING_DATASOURCE_PASSWORD
              value: "1234"
            - name: EXTERNAL_AI_IMAGE_URL
              value: http://ai-image-serving-predictor.ms-models.svc.cluster.local/v1/models/mobilenet:predict
            - name: EXTERNAL_AI_IMAGE_HOST
              value: ai-image-serving-predictor.ms-models.svc.cluster.local
            - name: EXTERNAL_AI_TEXT_URL
              value: http://ai-text-serving-predictor.ms-models.svc.cluster.local/v1/models/kobart-summary:predict
            - name: EXTERNAL_AI_TEXT_HOST
              value: ai-text-serving-predictor.ms-models.svc.cluster.local
"@
}

Invoke-Step "Deploy API Gateway Knative Service and Istio Gateway" {
    Apply-Yaml @"
apiVersion: serving.knative.dev/v1
kind: Service
metadata:
  name: api-gateway
  namespace: ms-gateway
spec:
  template:
    metadata:
      annotations:
        autoscaling.knative.dev/minScale: "1"
        autoscaling.knative.dev/maxScale: "5"
        autoscaling.knative.dev/target: "50"
    spec:
      containers:
        - image: $GatewayImage
          imagePullPolicy: $ImagePullPolicy
          ports:
            - containerPort: 8088
          env:
            - name: PORT
              value: "8088"
            - name: BACKEND_URL
              value: http://ms-backend.ms-backend.svc.cluster.local
            - name: ALLOWED_ORIGINS
              value: $FrontendOrigin
---
apiVersion: networking.istio.io/v1beta1
kind: Gateway
metadata:
  name: ms-serving-gateway
  namespace: ms-gateway
spec:
  selector:
    istio: ingressgateway
  servers:
    - port:
        number: 80
        name: http
        protocol: HTTP
      hosts:
        - "*"
---
apiVersion: networking.istio.io/v1beta1
kind: VirtualService
metadata:
  name: api-gateway
  namespace: ms-gateway
spec:
  hosts:
    - "*"
  gateways:
    - ms-serving-gateway
  http:
    - name: api
      match:
        - uri:
            prefix: /
      route:
        - destination:
            host: api-gateway.ms-gateway.svc.cluster.local
            port:
              number: 80
          headers:
            request:
              set:
                Host: api-gateway.ms-gateway.svc.cluster.local
      timeout: 60s
"@
}

Invoke-Step "Expose Istio ingressgateway on localhost" {
    Wait-For-IngressGatewayService
    Start-IngressPortForward -LocalPort $IngressLocalPort
}

if (-not $SkipKServe) {
    Invoke-Step "Install cert-manager and KServe" {
        kubectl apply -f https://github.com/cert-manager/cert-manager/releases/download/v1.17.2/cert-manager.yaml

        kubectl wait --for condition=established --timeout=60s crd/certificates.cert-manager.io
        kubectl wait --for condition=established --timeout=60s crd/certificaterequests.cert-manager.io
        kubectl wait --for condition=established --timeout=60s crd/issuers.cert-manager.io
        kubectl wait --for condition=established --timeout=60s crd/clusterissuers.cert-manager.io

        kubectl wait --for=condition=Ready pod -l app=cert-manager -n cert-manager --timeout=300s
        kubectl wait --for=condition=Ready pod -l app=cainjector -n cert-manager --timeout=300s
        kubectl wait --for=condition=Ready pod -l app=webhook -n cert-manager --timeout=300s

        kubectl apply --server-side -f https://github.com/kserve/kserve/releases/download/v0.15.0/kserve.yaml
        kubectl apply --server-side -f https://github.com/kserve/kserve/releases/download/v0.15.0/kserve-cluster-resources.yaml

        kubectl apply -f (Join-Path $InfraDir "Kserve-ai-image-serving.yaml")
        kubectl apply -f (Join-Path $InfraDir "Kserve-ai-text-serving.yaml")
    }
}

Write-Host ""
Write-Host "Setup complete!" -ForegroundColor Green
Write-Host "API Gateway: $ApiBaseUrl" -ForegroundColor Green
Write-Host ""
Write-Host "Put these values into ms-frontend/.env.local, then run npm run dev:"
Write-Host "NEXT_PUBLIC_API_URL=$ApiBaseUrl"
Write-Host "NEXT_PUBLIC_GRAFANA_URL=$($ParsedApiBaseUrl.Scheme)://grafana.$ObservabilityBaseHost$ObservabilityPort"
Write-Host "NEXT_PUBLIC_KIALI_URL=$($ParsedApiBaseUrl.Scheme)://kiali.$ObservabilityBaseHost$ObservabilityPort"
