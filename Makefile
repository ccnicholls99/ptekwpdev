APP_BASE := $(CURDIR)
CONFIG_BASE := $(HOME)/.ptekwpdev

REQUIRED_BINS := jq docker envsubst

.PHONY: setup provision clean check-binaries

check-binaries:
	@for bin in $(REQUIRED_BINS); do \
		if ! command -v $$bin >/dev/null 2>&1; then \
			echo "[ERR] Required binary '$$bin' not found in PATH"; \
			exit 1; \
		fi; \
	done
	@echo "[INFO] All required binaries are present"

setup: check-binaries
	@$(APP_BASE)/bin/setup.sh

provision: check-binaries
	@if [ -z "$(PROJECT)" ]; then \
		echo "[ERR] Must specify PROJECT, e.g. 'make provision PROJECT=splatt'"; \
		exit 1; \
	fi
	@$(APP_BASE)/bin/provision.sh --project $(PROJECT)

clean:
	@echo "[INFO] Cleaning generated workspace"
	@rm -rf $(CONFIG_BASE)/config $(CONFIG_BASE)/secrets $(CONFIG_BASE)/certs $(CONFIG_BASE)/assets