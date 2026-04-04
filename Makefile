.PHONY: test test-unit test-integration test-e2e deps

DEPS_DIR = .deps
PLENARY_DIR = $(DEPS_DIR)/plenary.nvim

$(PLENARY_DIR):
	git clone --depth 1 https://github.com/nvim-lua/plenary.nvim $(PLENARY_DIR)

deps: $(PLENARY_DIR)

test: deps test-unit test-integration

test-unit: deps
	nvim --headless -u tests/minimal_init.lua -c "PlenaryBustedDirectory tests/unit/"

test-integration: deps
	nvim --headless -u tests/minimal_init.lua -c "PlenaryBustedDirectory tests/integration/"

test-e2e: deps
	nvim --headless -u tests/minimal_init.lua -c "PlenaryBustedDirectory tests/e2e/"
