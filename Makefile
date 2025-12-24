# ---------------------------------------------------------
# Config
# ---------------------------------------------------------
CONFIG_FILE := $(HOME)/.ptekwpdev/environments.json
APP_PROJECT_BASE := $(shell jq -r '.app.project_base' $(CONFIG_FILE))
PROJECT_BASE := $(shell jq -r ".environments[\"$(PROJECT)\"].base_dir" $(CONFIG_FILE) | sed 's|^/||')
PROJECT_NAME := $(shell jq -r ".environments[\"$(PROJECT)\"].project_name" $(CONFIG_FILE))

# ---------------------------------------------------------
# Guards
# ---------------------------------------------------------
require-project:
	@if [ -z "$(PROJECT)" ]; then \
		echo "PROJECT is required. Usage: make <target> PROJECT=<name>"; \
		exit 1; \
	fi

# ---------------------------------------------------------
# App-level deployment
# ---------------------------------------------------------
app-init:
	@bin/deploy_app.sh -a init

app-up:
	@bin/deploy_app.sh -a up

app-down:
	@bin/deploy_app.sh -a down

app-reset:
	@bin/deploy_app.sh -a reset

# ---------------------------------------------------------
# Project-level deployment
# ---------------------------------------------------------
provision: require-project
	@echo "Provisioning project: $(PROJECT_NAME)"
	@bin/deploy_project.sh --project $(PROJECT)

certs: require-project
	@echo "Generating dev SSL certificates for project: $(PROJECT_NAME)"
	@bin/generate_certs.sh --project $(PROJECT)

build: require-project
	@echo "Building Docker environment for project: $(PROJECT_NAME)"
	@bin/build.sh --project $(PROJECT)

autoinstall: require-project
	@echo "Running WordPress auto-install for project: $(PROJECT_NAME)"
	@bin/autoinstall.sh --project $(PROJECT)

setup: require-project
	@$(MAKE) provision PROJECT=$(PROJECT)
	@$(MAKE) certs PROJECT=$(PROJECT)
	@$(MAKE) build PROJECT=$(PROJECT)
	@$(MAKE) autoinstall PROJECT=$(PROJECT)

# ---------------------------------------------------------
# Cleanup
# ---------------------------------------------------------
clean: require-project
	@if [ -z "$(PROJECT_BASE)" ] || [ "$(PROJECT_BASE)" = "/" ]; then \
		echo "Refusing to clean: PROJECT_BASE is unsafe"; \
		exit 1; \
	fi
	@echo "Cleaning project: $(PROJECT_NAME)"
	@rm -rf $(APP_PROJECT_BASE)/$(PROJECT_BASE)
	@echo "Removed $(APP_PROJECT_BASE)/$(PROJECT_BASE)"

clean-project: require-project
	@bin/cleanup-project.sh $(PROJECT) --no-prompt

clean-all-projects:
	@bin/cleanup-project.sh --all --no-prompt

clean-all:
	@bin/cleanup-all.sh --no-prompt

# ---------------------------------------------------------
# Assets
# ---------------------------------------------------------
assets:
	@bin/assets.sh --action $(ACTION) --type $(TYPE) --name $(NAME) --version $(VERSION) --src $(SRC)

.PHONY: app-init app-up app-down app-reset \
        provision certs build autoinstall setup \
        clean clean-project clean-all-projects clean-all \
        assets require-project