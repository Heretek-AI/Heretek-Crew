# Heretek-Crew operations Makefile.
#
# Every target is documented (see `make help`). All docker work goes through
# `docker compose`; secrets come from `.env` (copied from `.env.example`),
# never from the Makefile. Versions are pinned in docker/Dockerfile and
# docker-compose.yml — never `latest`.
#
# Typical flow:
#   cp .env.example .env   # then fill in secrets
#   make build && make up && make seed
#   make test              # smoke test (static checks; live when stack is up)

# Load .env when present so compose sub-commands and scripts see the same
# values. `-include` keeps this a no-op before the first `cp .env.example .env`.
-include .env
export

COMPOSE := docker compose
BACKUP_SCRIPT := ./scripts/backup-db.sh
RESTORE_SCRIPT := ./scripts/restore-db.sh
SEED_SCRIPT := ./scripts/seed-company.sh
SEED_50_SCRIPT := ./scripts/seed-50-fleet.sh
GENERATE_ROLES_SCRIPT := ./scripts/generate-50-roles.py
SMOKE_SCRIPT := ./scripts/smoke-test.sh

.DEFAULT_GOAL := help
.PHONY: help build up down logs seed seed-50 generate-roles backup restore test

help: ## Show this help (lists all documented targets).
	@echo "Heretek-Crew — Paperclip + OpenCode v2 stack"
	@echo ""
	@echo "Quickstart: cp .env.example .env  # edit secrets"
	@echo "            make build && make up && make seed"
	@echo ""
	@grep -E '^[a-zA-Z0-9_-]+:.*?## ' $(MAKEFILE_LIST) | \
		awk 'BEGIN {FS = ":.*?## "}; {printf "  %-10s %s\n", $$1, $$2}'

build: ## Build the Paperclip + OpenCode v2 Docker image.
	$(COMPOSE) build

up: ## Start the stack in background (postgres + paperclip, private on 127.0.0.1:3100).
	$(COMPOSE) up -d

down: ## Stop the stack (containers kept; data in named volumes is preserved).
	$(COMPOSE) down

logs: ## Follow logs of the paperclip service (Ctrl-C to stop).
	$(COMPOSE) logs -f paperclip

seed: ## Seed the company and 6-agent fleet (idempotent; see scripts/seed-company.sh --help).
	$(SEED_SCRIPT)

generate-roles: ## Scaffold the 50-agent fleet on disk (idempotent; see scripts/generate-50-roles.py --help).
	python3 $(GENERATE_ROLES_SCRIPT)

seed-50: ## Seed the 50-agent fleet (idempotent; see scripts/seed-50-fleet.sh --help).
	$(SEED_50_SCRIPT)

backup: ## Create a timestamped database dump in backups/ (with retention pruning).
	$(BACKUP_SCRIPT)

restore: ## Restore a dump: make restore FILE=backups/backup-YYYYMMDD-HHMMSS.sql.gz
	@if [ -z "$(FILE)" ]; then \
		echo "error: FILE= is required" >&2; \
		echo "usage: make restore FILE=backups/backup-YYYYMMDD-HHMMSS.sql.gz" >&2; \
		exit 1; \
	fi
	FILE="$(FILE)" $(RESTORE_SCRIPT)

test: ## Run the end-to-end smoke test (static checks; live checks when the stack is up).
	$(SMOKE_SCRIPT)

worktree-create: ## Create isolated ticket worktree: make worktree-create TICKET=tkt-101 [BRANCH=main]
	@if [ -z "$(TICKET)" ]; then echo "error: TICKET= is required" >&2; exit 1; fi
	./scripts/worktree-manager.sh create "$(TICKET)" "$${BRANCH:-main}"

worktree-archive: ## Archive ticket worktree: make worktree-archive TICKET=tkt-101 [BRANCH=main]
	@if [ -z "$(TICKET)" ]; then echo "error: TICKET= is required" >&2; exit 1; fi
	./scripts/worktree-manager.sh archive "$(TICKET)" "$${BRANCH:-main}"

pipeline-dry-run: ## Trace 6-phase autonomous relay pipeline: make pipeline-dry-run PROMPT="Feature desc"
	./scripts/dispatch-pipeline.sh --dry-run "$${PROMPT:-Build test feature}"

