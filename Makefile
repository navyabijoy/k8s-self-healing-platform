DOCKERHUB_USER ?= your-dockerhub-username
APP_IMAGE      := $(DOCKERHUB_USER)/self-healing-eks-app
BOT_IMAGE      := $(DOCKERHUB_USER)/self-healing-eks-bot
TAG            := latest

.PHONY: help
help:
	@echo ""
	@echo "Self-Healing EKS Command Interface"
	@echo "=================================="
	@echo ""
	@echo "  CLUSTER SETUP"
	@echo "  make minikube-start          Start minikube with required resources"
	@echo "  make install-ingress         Install nginx ingress controller"
	@echo "  make install-monitoring      Install Prometheus + Grafana stack"
	@echo "  make install-all             Full setup from scratch"
	@echo ""
	@echo "  APP"
	@echo "  make build                   Build app Docker image locally"
	@echo "  make push                    Push image to Docker Hub"
	@echo "  make deploy-app              Deploy app + postgres to minikube"
	@echo "  make deploy-bot              Deploy remediation bot"
	@echo "  make deploy-monitoring       Apply alert rules + servicemonitor"
	@echo ""
	@echo "  DEMO / TESTING"
	@echo "  make simulate-crash          Hit /crash endpoint (triggers CrashLoopBackOff)"
	@echo "  make simulate-load           Hit /load endpoint (triggers HighCPU alert)"
	@echo "  make watch-pods              Watch pod status in real-time"
	@echo "  make watch-hpa               Watch HPA scaling in real-time"
	@echo ""
	@echo "  ACCESS"
	@echo "  make port-app                Forward app to localhost:8000"
	@echo "  make port-grafana            Forward Grafana to localhost:3000"
	@echo "  make port-prometheus         Forward Prometheus to localhost:9090"
	@echo "  make port-alertmanager       Forward Alertmanager to localhost:9093"
	@echo "  make port-bot                Forward remediation bot to localhost:9000"
	@echo "  make open-grafana            Open Grafana in browser (after port-forward)"
	@echo ""
	@echo "  LOGS"
	@echo "  make logs-app                Stream app pod logs"
	@echo "  make logs-bot                Stream remediation bot logs"
	@echo ""
	@echo "  TERRAFORM"
	@echo "  make tf-init                 terraform init"
	@echo "  make tf-validate             terraform fmt + validate"
	@echo "  make tf-plan                 terraform plan"
	@echo ""
	@echo "  CLEANUP"
	@echo "  make clean                   Remove all deployed resources"
	@echo "  make minikube-stop           Stop minikube"
	@echo "  make minikube-delete         Delete minikube cluster completely"
	@echo ""

.PHONY: minikube-start
minikube-start:
	@echo "Starting minikube..."
	minikube start \
		--cpus=4 \
		--memory=6144 \
		--disk-size=20g \
		--driver=docker \
		--kubernetes-version=v1.29.0
	minikube addons enable metrics-server
	minikube addons enable ingress
	@echo "minikube started successfully!"

.PHONY: install-ingress
install-ingress:
	@echo "Enabling minikube ingress addon..."
	minikube addons enable ingress
	@echo "Waiting for ingress controller pod to be ready..."
	kubectl wait --namespace ingress-nginx \
		--for=condition=ready pod \
		--selector=app.kubernetes.io/component=controller \
		--timeout=180s || true
	@echo "Ingress controller ready"

.PHONY: install-monitoring
install-monitoring:
	@echo "Installing kube-prometheus-stack (Prometheus + Grafana + Alertmanager)..."
	helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
	helm repo update
	helm upgrade --install kube-prometheus-stack prometheus-community/kube-prometheus-stack \
		--namespace monitoring \
		--create-namespace \
		--values helm/prometheus-values.yaml \
		--wait \
		--timeout 8m
	@echo "Monitoring stack installed!"

.PHONY: install-all
install-all: minikube-start install-ingress install-monitoring deploy-app deploy-bot deploy-monitoring
	@echo ""
	@echo "Full stack deployed!"
	@echo ""
	@echo "Next steps:"
	@echo "  make port-grafana     -> Open Grafana dashboard"
	@echo "  make simulate-crash   -> Trigger crash loop demo"
	@echo "  make simulate-load    -> Trigger CPU spike demo"

.PHONY: build
build:
	@echo "Building app image..."
	docker build \
		--build-arg BUILD_TIME=$(shell date -u +'%Y-%m-%dT%H:%M:%SZ') \
		--build-arg GIT_COMMIT=$(shell git rev-parse --short HEAD 2>/dev/null || echo 'unknown') \
		-t $(APP_IMAGE):$(TAG) \
		./app
	@echo "Built: $(APP_IMAGE):$(TAG)"

.PHONY: build-bot
build-bot:
	@echo "Building remediation bot image..."
	docker build -t $(BOT_IMAGE):$(TAG) ./remediation
	@echo "Built: $(BOT_IMAGE):$(TAG)"

.PHONY: push
push: build
	docker push $(APP_IMAGE):$(TAG)
	@echo "Pushed: $(APP_IMAGE):$(TAG)"

.PHONY: push-bot
push-bot: build-bot
	docker push $(BOT_IMAGE):$(TAG)
	@echo "Pushed: $(BOT_IMAGE):$(TAG)"

.PHONY: build-minikube
build-minikube:
	@echo "Building image inside minikube..."
	eval $$(minikube docker-env) && \
		docker build -t $(APP_IMAGE):$(TAG) ./app && \
		docker build -t $(BOT_IMAGE):$(TAG) ./remediation
	@echo "Images built in minikube's Docker daemon"

.PHONY: deploy-app
deploy-app:
	@echo "Deploying app + postgres..."
	kubectl apply -f k8s/namespace.yaml
	kubectl apply -f k8s/postgres.yaml
	kubectl apply -f k8s/deployment.yaml
	kubectl apply -f k8s/service.yaml
	kubectl apply -f k8s/hpa.yaml
	kubectl apply -f k8s/pdb.yaml
	kubectl apply -f k8s/ingress.yaml
	kubectl apply -f k8s/servicemonitor.yaml
	@echo "Waiting for app to be ready..."
	kubectl rollout status deployment/demo-app -n app --timeout=120s
	@echo "App deployed successfully!"
	kubectl get pods -n app

.PHONY: deploy-bot
deploy-bot:
	@echo "Deploying remediation bot..."
	kubectl apply -f k8s/remediation-bot.yaml
	kubectl rollout status deployment/remediation-bot -n monitoring --timeout=60s
	@echo "Remediation bot deployed successfully!"

.PHONY: deploy-monitoring
deploy-monitoring:
	@echo "Applying alert rules and service monitors..."
	kubectl apply -f monitoring/alert-rules.yaml
	@echo "Alert rules applied successfully!"

.PHONY: simulate-crash
simulate-crash:
	@echo "Simulating crash (hitting /crash endpoint)..."
	@echo "Watch: make watch-pods"
	@echo ""
	$(eval APP_URL := $(shell kubectl get svc demo-app-service -n app -o jsonpath='{.spec.clusterIP}'):80)
	kubectl run crash-trigger --rm -it --restart=Never \
		--image=curlimages/curl:latest \
		-- sh -c 'for i in 1 2 3 4 5 6; do echo "Crash $$i:"; curl -s http://demo-app-service.app.svc.cluster.local/crash || true; sleep 2; done'

.PHONY: simulate-load
simulate-load:
	@echo "Simulating CPU load (60 seconds)..."
	kubectl run load-trigger --rm -it --restart=Never \
		--image=curlimages/curl:latest \
		-- curl -X POST "http://demo-app-service.app.svc.cluster.local/load?seconds=60"

.PHONY: watch-pods
watch-pods:
	kubectl get pods -n app -o wide -w

.PHONY: watch-hpa
watch-hpa:
	kubectl get hpa -n app -w

.PHONY: port-app
port-app:
	@echo "App running at http://localhost:8000"
	kubectl port-forward svc/demo-app-service 8000:80 -n app

.PHONY: port-grafana
port-grafana:
	@echo "Grafana running at http://localhost:3000"
	@echo "Login: admin / grafana-admin-pass"
	kubectl port-forward svc/kube-prometheus-stack-grafana 3000:80 -n monitoring

.PHONY: port-prometheus
port-prometheus:
	@echo "Prometheus running at http://localhost:9090"
	kubectl port-forward svc/kube-prometheus-stack-prometheus 9090:9090 -n monitoring

.PHONY: port-alertmanager
port-alertmanager:
	@echo "Alertmanager running at http://localhost:9093"
	kubectl port-forward svc/kube-prometheus-stack-alertmanager 9093:9093 -n monitoring

.PHONY: port-bot
port-bot:
	@echo "Remediation bot running at http://localhost:9000"
	kubectl port-forward svc/remediation-bot-service 9000:9000 -n monitoring

.PHONY: open-grafana
open-grafana:
	open http://localhost:3000

.PHONY: logs-app
logs-app:
	kubectl logs -f deploy/demo-app -n app --all-containers

.PHONY: logs-bot
logs-bot:
	kubectl logs -f deploy/remediation-bot -n monitoring

TF_DIR := terraform/environments/dev

.PHONY: tf-init
tf-init:
	cd $(TF_DIR) && terraform init -backend=false

.PHONY: tf-validate
tf-validate:
	cd $(TF_DIR) && terraform fmt -recursive ../.. && terraform validate
	@echo "Terraform is valid!"

.PHONY: tf-plan
tf-plan:
	@echo "Running terraform plan..."
	cd $(TF_DIR) && terraform plan -var="db_password=demo-password-not-real"

.PHONY: clean
clean:
	@echo "Removing all deployed resources..."
	kubectl delete namespace app --ignore-not-found
	@echo "Cleaned up 'app' namespace"

.PHONY: clean-monitoring
clean-monitoring:
	helm uninstall kube-prometheus-stack -n monitoring || true
	helm uninstall grafana -n monitoring || true

.PHONY: minikube-stop
minikube-stop:
	minikube stop

.PHONY: minikube-delete
minikube-delete:
	minikube delete
	@echo "minikube cluster deleted"
