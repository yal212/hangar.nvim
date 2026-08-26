# Developer entry points. CI runs these same targets, so "passing locally" and
# "passing in CI" cannot drift apart.
#
#   make check     everything CI runs
#   make test      offline suite
#   make test-one FILTER=codex   one spec

NVIM ?= nvim
LUA_PATHS := lua plugin tests scripts assets/demo/init.lua
SH_PATHS := assets/demo/fake-claude assets/demo/seed-repo.sh $(wildcard scripts/*.sh)

.PHONY: check test test-one fmt lint typecheck docs coverage hooks integration help

help: ## Show this help
	@grep -hE '^[a-z-]+:.*##' $(MAKEFILE_LIST) | sed 's/:.*##/\t/' | expand -t22

check: lint typecheck test docs ## Everything CI runs

test: ## Offline test suite
	$(NVIM) --headless -l tests/run_tests.lua

test-one: ## One spec: make test-one FILTER=codex
	@test -n "$(FILTER)" || { echo "usage: make test-one FILTER=<substring>"; exit 2; }
	$(NVIM) --headless -l tests/run_tests.lua --filter $(FILTER)

integration: ## Real agent runs — COSTS MONEY. make integration ADAPTERS="codex"
	XDG_DATA_HOME=$$(mktemp -d) $(NVIM) --headless -l tests/run_tests.lua --integration $(ADAPTERS)

fmt: ## Format Lua in place
	stylua $(LUA_PATHS)

lint: ## stylua --check, luacheck, shellcheck
	stylua --check $(LUA_PATHS)
	luacheck $(LUA_PATHS)
	@command -v shellcheck >/dev/null && shellcheck $(SH_PATHS) || echo "shellcheck not installed — skipping"

typecheck: ## lua-language-server diagnostics
	@VIMRUNTIME="$$($(NVIM) --headless -c 'echo $$VIMRUNTIME' -c 'quit' 2>&1)" \
		lua-language-server --check . --checklevel=Warning --logpath=/tmp/hangar-lls

docs: ## Assert docs match the code
	$(NVIM) --headless -l scripts/check-docs.lua

coverage: ## Test suite with luacov report
	eval "$$(luarocks path)" && HANGAR_COVERAGE=1 $(NVIM) --headless -l tests/run_tests.lua && luacov \
		&& sed -n '/^Summary$$/,$$p' luacov.report.out

hooks: ## Install the pre-commit hook into .git/hooks
	install -m 755 scripts/hooks/pre-commit .git/hooks/pre-commit
	@echo "installed .git/hooks/pre-commit (runs 'make lint')"
