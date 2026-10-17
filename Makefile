# Heretek-Crew operations Makefile.
#
# Every target is documented (see `make help`). All docker work goes through
# `docker compose`; secrets come from `.env` (copied from `.env.example`),
# never from the Makefile. Versions are pinned in docker/Dockerfile and
# docker-compose.yml — never `latest`.
#
# Typical flow:
#   cp .env.example .env   # then fill in secrets
#   make build && make up && make seed-50
#   make test              # smoke test (static checks; live when stack is up)

# Load .env when present so compose sub-commands and scripts see the same
# values. `-include` keeps this a no-op before the first `cp .env.example .env`.
-include .env
export

COMPOSE := docker compose
# Wave 4 P1-12: privileged/high-capability sidecars must never share a
# scheduler invocation with the sensitive profiles. The `mobile` profile
# (privileged docker-android + /dev/kvm) is refused together with
# `devsec` (untrusted-sample RE tooling) or `web-research` (untrusted
# remote content ingestion). Fail-closed: any sidecar-up invocation
# listing mobile alongside devsec/web-research exits 1 before docker runs.
# Static gate: scripts/smoke-test.sh asserts this guard text is present.
SIDECAR_PROFILES ?=
guard-profiles: ## Fail-closed guard: refuse mobile+devsec/web-research co-scheduling.
	@case " $(SIDECAR_PROFILES) " in \
	  *" mobile "*|*"mobile,"*|*",mobile"*) \
	    case " $(SIDECAR_PROFILES) " in \
	      *" devsec "*|*"devsec,"*|*",devsec"*|*" web-research "*|*"web-research,"*|*",web-research"*) \
	        echo "error: refusing to co-schedule --profile mobile with devsec/web-research (P1-12: privileged emulator must stay isolated; run mobile alone on a dedicated host)" >&2; \
	        exit 1;; \
	    esac;; \
	esac

sidecars-up: guard-profiles ## Start sidecars: make sidecars-up SIDECAR_PROFILES="web-research" (mobile isolated; see guard-profiles).
	$(COMPOSE) -f docker-compose.yml -f docker-compose.sidecars.yml $(foreach p,$(SIDECAR_PROFILES),--profile $(p)) up -d

# Wave D P2-6: the caddy proxy binds 80/443 on ALL interfaces — intentional
# but one word away from an internet-facing auth surface. guard-proxy makes
# the exposure note in docker-compose.yml enforced, not honor-system:
# proxy-up refuses unless PAPERCLIP_DEPLOYMENT_EXPOSURE=private AND
# BETTER_AUTH_SECRET is set to a real (non-placeholder, non-empty)
# secret. (Compose already fail-closes a missing BETTER_AUTH_SECRET via
# :?; this gate additionally refuses placeholder values and non-private
# exposure.) Never bypass with raw `docker compose --profile proxy up`.
guard-proxy: ## Fail-closed guard: refuse --profile proxy unless exposure is private + auth secret is real.
	@if [ "$${PAPERCLIP_DEPLOYMENT_EXPOSURE:-private}" != "private" ]; then \
		echo "error: refusing --profile proxy with PAPERCLIP_DEPLOYMENT_EXPOSURE='$${PAPERCLIP_DEPLOYMENT_EXPOSURE}' (must be 'private')" >&2; \
		exit 1; \
	fi; \
	case "$${BETTER_AUTH_SECRET:-}" in \
	  ""|CHANGE_ME__*) \
		echo "error: refusing --profile proxy with missing/placeholder BETTER_AUTH_SECRET (provision a real secret first)" >&2; \
		exit 1;; \
	esac; \
	echo "proxy preflight OK (exposure=private, BETTER_AUTH_SECRET provisioned)"

proxy-up: guard-proxy ## Start the stack with the TLS reverse proxy (guarded; see guard-proxy).
	$(COMPOSE) --profile proxy up -d
COMPOSE_PREBUILT := $(COMPOSE) -f docker-compose.yml -f docker-compose.prebuilt.yml
BACKUP_SCRIPT := ./scripts/backup-db.sh
RESTORE_SCRIPT := ./scripts/restore-db.sh
SEED_50_SCRIPT := ./scripts/seed-50-fleet.sh
GENERATE_ROLES_SCRIPT := ./scripts/generate-50-roles.py
SMOKE_SCRIPT := ./scripts/smoke-test.sh

.DEFAULT_GOAL := help
.PHONY: help build up down logs seed-50 generate-roles backup restore test prebuilt-pull prebuilt-up prebuilt-config guard-profiles sidecars-up guard-proxy proxy-up

help: ## Show this help (lists all documented targets).
	@echo "Heretek-Crew — Paperclip + OpenCode v2 stack"
	@echo ""
	@echo "Quickstart: cp .env.example .env  # edit secrets"
	@echo "            make build && make up && make seed-50"
	@echo ""
	@grep -E '^[a-zA-Z0-9_-]+:.*?## ' $(MAKEFILE_LIST) | \
		awk 'BEGIN {FS = ":.*?## "}; {printf "  %-10s %s\n", $$1, $$2}'

build: ## Build the Paperclip + OpenCode v2 Docker image locally.
	# Build order matters (P3-5): the wave1 layer builds FROM
	# ${PAPERCLIP_BASE_IMAGE:-paperclip:official-local}, so build the official
	# base FIRST (docker build -t paperclip:official-local /tmp/paperclip)
	# or `docker compose build` below reuses a STALE base without warning.
	# See docker/Dockerfile (two-step build) and docker-compose.yml header.
	$(COMPOSE) build

up: ## Start the stack in background (postgres + paperclip, private on 127.0.0.1:3100).
	$(COMPOSE) up -d

prebuilt-pull: ## Pull the prebuilt image from GHCR without building locally.
	$(COMPOSE_PREBUILT) pull paperclip

prebuilt-up: ## Start the stack using the prebuilt GHCR image (postgres + paperclip).
	$(COMPOSE_PREBUILT) up -d

prebuilt-config: ## Validate the merged docker-compose config for the prebuilt setup.
	$(COMPOSE_PREBUILT) config

down: ## Stop the stack (containers kept; data in named volumes is preserved).
	$(COMPOSE) down

logs: ## Follow logs of the paperclip service (Ctrl-C to stop).
	$(COMPOSE) logs -f paperclip

# Wave 3 P1-11: `seed` (6-agent prototype seeder) removed with the legacy
# roles it seeded — the 50-fleet is the only role set; use `seed-50`.
generate-roles: ## Scaffold the 51-agent fleet on disk (idempotent; see scripts/generate-50-roles.py --help).
	python3 $(GENERATE_ROLES_SCRIPT)

seed-50: ## Seed the 51-agent fleet (idempotent; see scripts/seed-50-fleet.sh --help).
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

