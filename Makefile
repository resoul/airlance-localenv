GITHUB ?= git@github.com:resoul
REPOS ?= auth airlance-server Airlance

AUTH_ENV := auth/.secrets/production/airlance_auth.env
TUNNEL_ENV := auth/.secrets/production/cloudflared.env
SERVER_ENV := airlance-server/deploy/.env
AUTH := docker compose -f auth/deploy/compose.prod.yaml
SERVER := docker compose -f airlance-server/deploy/compose.yaml
AUTH_CLI := $(AUTH) exec -T airlance-auth /airlance-auth
WAIT_TRIES := 45
SCOPES := --scope profile:read --scope profile:write

.DEFAULT_GOAL := help
.PHONY: help setup check-tunnel up wait-auth wait-server register down status logs update ios

help: ## Show commands
	@awk 'BEGIN {FS = ":.*## "} /^[a-z-]+:.*## / {printf "  make %-10s %s\n", $$1, $$2}' $(MAKEFILE_LIST)

setup: ## Clone missing repos and set up defaults once
	@for repo in $(REPOS); do \
		if [ -d "$$repo" ]; then echo "$$repo: already exists"; else git clone "$(GITHUB)/$$repo" "$$repo" || exit 1; fi; \
	done
	@if [ -e "$(AUTH_ENV)" ]; then \
		echo "auth: настройки уже есть"; \
	else \
		(cd auth && AIRLANCE_AUTH_OIDC=1 AIRLANCE_AUTH_COMPOSE_PROFILES=tunnel,mailpit scripts/init_production.sh) || exit 1; \
		sed -i.bak -e 's|^AIRLANCE_AUTH_SMTP_ADDR=$$|AIRLANCE_AUTH_SMTP_ADDR=mailpit:1025|' \
			-e 's|^AIRLANCE_AUTH_SMTP_TLS=.*|AIRLANCE_AUTH_SMTP_TLS=none|' "$(AUTH_ENV)" && rm "$(AUTH_ENV).bak"; \
	fi
	@if [ -e "$(SERVER_ENV)" ]; then echo "airlance-server: настройки уже есть"; else airlance-server/scripts/init.sh; fi
	@if ! grep -Eq '^TUNNEL_TOKEN=[^<[:space:]]+' "$(TUNNEL_ENV)"; then \
		echo "Missing tunnel token in $(TUNNEL_ENV), set it manually" >&2; \
	fi

check-tunnel:
	@grep -Eq '^TUNNEL_TOKEN=[^<[:space:]]+' "$(TUNNEL_ENV)" || { \
		echo "Missing tunnel token in $(TUNNEL_ENV)" >&2; exit 1; \
	}

up: check-tunnel ## Start auth, wait for it, then start server
	$(AUTH) up -d --build --remove-orphans
	@$(MAKE) --no-print-directory wait-auth
	$(SERVER) up -d --build --remove-orphans
	@$(MAKE) --no-print-directory wait-server

wait-auth:
	@tries=0; until $(AUTH_CLI) healthcheck >/dev/null 2>&1; do \
		tries=$$((tries + 1)); \
		if [ $$tries -ge $(WAIT_TRIES) ]; then echo "auth not ready" >&2; exit 1; fi; \
		sleep 2; \
	done; echo "auth ready"

wait-server:
	@tries=0; until $(SERVER) exec -T airlance-server /airlance-server healthcheck >/dev/null 2>&1; do \
		tries=$$((tries + 1)); \
		if [ $$tries -ge $(WAIT_TRIES) ]; then echo "server not ready" >&2; exit 1; fi; \
		sleep 2; \
	done; echo "server ready"

register: ## Register airlance-ios and messenger-api in auth, repeat safely
	@if $(AUTH_CLI) oidc client list | grep -q '^airlance-ios[[:space:]]'; then \
		echo "airlance-ios: уже есть"; \
	else \
		$(AUTH_CLI) oidc client create airlance-ios --name Airlance --native --redirect-uri airlance://auth/callback; \
	fi
	@if $(AUTH_CLI) oidc resource list | grep -q '^messenger-api[[:space:]]'; then \
		echo "messenger-api: уже есть"; \
	else \
		$(AUTH_CLI) oidc resource register messenger-api --name Messenger --uri https://api.airlance.org \
			--audience messenger-api $(SCOPES); \
	fi
	@$(AUTH_CLI) oidc resource allow messenger-api --client airlance-ios $(SCOPES)

down: ## Stop everything, data is saved
	$(SERVER) down
	$(AUTH) down

status: ## Show containers and public addresses
	@$(AUTH) ps
	@$(SERVER) ps
	@for url in https://auth.airlance.org/health/ready https://api.airlance.org/health/ready; do \
		printf '%s ' "$$url"; curl -s -o /dev/null -w '%{http_code}\n' --max-time 10 "$$url" || echo; \
	done

logs: ## Show logs: make logs, make logs s=auth, make logs s=server
	@case "$(s)" in \
		auth) $(AUTH) logs -f --tail=100 ;; \
		server) $(SERVER) logs -f --tail=100 ;; \
		"") $(AUTH) logs --tail=50; $(SERVER) logs --tail=50 ;; \
		*) echo "s может быть auth или server" >&2; exit 1 ;; \
	esac

update: ## Get fresh code and rebuild
	@failed=0; for repo in $(REPOS); do \
		echo "$$repo:"; git -C "$$repo" pull --ff-only || failed=1; \
	done; \
	if [ $$failed -ne 0 ]; then echo "Not all repositories updated, I'm not touching the stack" >&2; exit 1; fi
	@$(MAKE) --no-print-directory up

ios: ## Install application on connected phone
	$(MAKE) -C Airlance device
