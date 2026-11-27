# AAP (AWX) + CyberArk Conjur demo
#
#   make setup
#   make demo
#   make down

SHELL := /bin/bash
ROOT  := $(abspath $(dir $(lastword $(MAKEFILE_LIST))))
export PATH := /Applications/UTM.app/Contents/MacOS:$(PATH)
export KIND_EXPERIMENTAL_PROVIDER ?= podman

.DEFAULT_GOAL := help

.PHONY: help setup demo status down clean

help: ## Show targets
	@awk 'BEGIN {FS = ":.*##"; printf "\nUsage: make \033[36m<target>\033[0m\n\n"} \
		/^[a-zA-Z0-9_-]+:.*?##/ { printf "  \033[36m%-10s\033[0m %s\n", $$1, $$2 }' $(MAKEFILE_LIST)

setup: ## Bootstrap Conjur, target VM, Controller, and Conjur-backed credentials
	"$(ROOT)/scripts/setup.sh"

demo: ## Launch Job Template (Conjur → Machine SSH key → ping)
	"$(ROOT)/controller/scripts/demo.sh"

status: ## Show stack health
	@echo "== Conjur =="; curl -sk -o /dev/null -w 'https://localhost:8443 → %{http_code}\n' https://localhost:8443/ || true
	@echo "== Target =="; cd "$(ROOT)/vagrant" && vagrant status || true
	@echo "== Controller =="; kind get clusters 2>/dev/null || true; kubectl -n awx get pods 2>/dev/null || true
	@[[ -f "$(ROOT)/controller/.controller.env" ]] && grep '^CONTROLLER_' "$(ROOT)/controller/.controller.env" || true

down: ## Stop VM, Conjur, and kind cluster
	@cd "$(ROOT)/vagrant" && vagrant halt || true
	@cd "$(ROOT)/conjur" && export CONJUR_DATA_KEY="$$(tr -d '\r\n' < data_key 2>/dev/null || true)" && podman compose down || true
	@kind delete cluster --name aap-cyberark-demo 2>/dev/null || true
	@echo "Stopped."

clean: down ## Stop stack and delete generated secrets/keys/VM
	@rm -f "$(ROOT)/conjur/data_key" "$(ROOT)/conjur/admin_data" "$(ROOT)/conjur/admin_api_key" \
		"$(ROOT)/conjur/policy_data" "$(ROOT)/conjur/host_api_key" "$(ROOT)/conjur/conjur-server.pem"
	@rm -f "$(ROOT)/conjur/conf/tls/nginx.crt" "$(ROOT)/conjur/conf/tls/nginx.key"
	@rm -f "$(ROOT)/keys/id_ed25519" "$(ROOT)/keys/id_ed25519.pub"
	@rm -f "$(ROOT)/controller/.controller.env"
	@cd "$(ROOT)/vagrant" && vagrant destroy -f || true
	@echo "Cleaned."
