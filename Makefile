# Canopy node stack
SHELL := /bin/bash

# Load environment variables from .env if it exists
ifneq (,$(wildcard .env))
  include .env
  export
endif

NODE_COMPOSE := docker-compose.yml
MONITORING_COMPOSE := docker-compose.monitoring.yml
ROOTCHAIN_COMPOSE := docker-compose.rootchain-local.yml
FULL_COMPOSE := docker compose -f $(NODE_COMPOSE) -f $(MONITORING_COMPOSE)
# For commands that create nothing (down, ps): the monitoring compose requires
# its credentials to be set, which a node-only setup may not have.
FULL_COMPOSE_NOCREDS := AUTH_PASSWORDHASH="$${AUTH_PASSWORDHASH:-unused}" GF_ADMIN_PASSWORD="$${GF_ADMIN_PASSWORD:-unused}" $(FULL_COMPOSE)

# Same caddy version as the stack (single source: docker-compose.monitoring.yml).
CADDY_IMAGE := $(shell awk '/image: caddy:/ {print $$2; exit}' $(MONITORING_COMPOSE))
# Node image; override with CANOLIQ_NODE_IMAGE in .env to pin a version.
NODE_IMAGE := $(or $(CANOLIQ_NODE_IMAGE),canopynetwork/canopy-plugin-go:latest)

.PHONY: help hash-password check-env pull up down restart logs status validate gen-key snapshot snapshot-up node-up node-up-local-rootchain

help: ## Show available targets
	@grep -hE '^[a-zA-Z_-]+:.*## ' $(MAKEFILE_LIST) | awk -F':.*## ' '{printf "  %-16s %s\n", $$1, $$2}'

hash-password: ## Generate a bcrypt hash for AUTH_PASSWORDHASH (prompts for password)
	@read -s -p "Password: " pw; echo; \
	printf "AUTH_PASSWORDHASH="; \
	docker run --rm -i $(CADDY_IMAGE) caddy hash-password -p "$$pw" | sed 's/\$$/\$$\$$/g'
	@echo "Copy the exact line above into .env"

check-env: ## Refuse known-public or missing credentials in .env
	@./scripts/check-env.sh

pull: ## Pull the node image (CANOLIQ_NODE_IMAGE, default :latest)
	docker compose -f $(NODE_COMPOSE) pull canoliq-node

node-up: check-env ## Start the node only (no monitoring)
	docker compose -f $(NODE_COMPOSE) up -d canoliq-node

node-up-local-rootchain: check-env ## Start the node, joined to a chain-1 node on this machine
	docker compose -f $(NODE_COMPOSE) -f $(ROOTCHAIN_COMPOSE) up -d canoliq-node

up: ## Starts everything (node, monitoring, etc.)
	@./scripts/check-env.sh --monitoring
	$(FULL_COMPOSE) up -d

down: ## Stop everything
	$(FULL_COMPOSE_NOCREDS) down

restart: ## Restart the nodes (reload config.json changes)
	docker compose -f $(NODE_COMPOSE) restart canoliq-node

logs: ## Tail node logs
	docker compose -f $(NODE_COMPOSE) logs -f canoliq-node --tail 200

status: ## Show container status
	$(FULL_COMPOSE_NOCREDS) ps

snapshot: ## Restore chain data from the public canoLiq snapshot (stops the node first)
	./scripts/snapshot.sh

snapshot-up: snapshot up ## Restore from snapshot, then start everything

gen-key: ## First-boot: generate validator key (written with mode 600)
	@docker run --rm -it \
		--entrypoint /bin/sh \
		-v "$(CURDIR)/config:/app/config" \
		$(NODE_IMAGE) \
		-c 'umask 077 && /bin/cli new-validator-key --data-dir /app/config && chmod 600 /app/config/validator_key.json /app/config/keystore.json'
	@echo "Key files are mode 600. Back them up somewhere safe and offline."
