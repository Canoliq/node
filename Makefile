# Canopy node stack
SHELL := /bin/bash

# Load environment variables from .env if it exists
ifneq (,$(wildcard .env))
  include .env
  export
endif

NODE_COMPOSE := docker-compose.yml
MONITORING_COMPOSE := docker-compose.monitoring.yml
FULL_COMPOSE := docker compose -f $(NODE_COMPOSE) -f $(MONITORING_COMPOSE)

.PHONY: help hash-password up down restart logs status validate gen-key

help: ## Show available targets
	@grep -hE '^[a-zA-Z_-]+:.*## ' $(MAKEFILE_LIST) | awk -F':.*## ' '{printf "  %-16s %s\n", $$1, $$2}'

hash-password: ## Generate a bcrypt hash for AUTH_PASSWORDHASH (prompts for password)
	@read -s -p "Password: " pw; echo; \
	printf "AUTH_PASSWORDHASH="; \
	docker run --rm -i caddy:2.10-alpine caddy hash-password -p "$$pw" | sed 's/\$$/\$$\$$/g'
	@echo "Copy the exact line above into .env"

pull: ## Pull the latest canopynetwork/canopy-plugin-go image
	$(FULL_COMPOSE) pull node

node-up: ## Start the node only (no monitoring)
	docker compose -f $(NODE_COMPOSE) up -d node

up: ## Starts everything (node, monitoring, etc.)
	$(FULL_COMPOSE) up -d

down: ## Stop everything
	$(FULL_COMPOSE) --profile monitoring down

restart: ## Restart the nodes (reload config.json changes)
	$(FULL_COMPOSE) restart node

logs: ## Tail node logs
	docker compose -f $(NODE_COMPOSE) logs -f node --tail 200

status: ## Show container status
	$(FULL_COMPOSE) ps

gen-key: ## First-boot: generate validator key
	@docker run --rm -it \
		--entrypoint /bin/cli \
		-v "$(CURDIR)/config:/app/config" \
		canopynetwork/canopy-plugin-go:latest \
		new-validator-key --data-dir /app/config
