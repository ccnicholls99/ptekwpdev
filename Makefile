# Require PROJECT to be set for project-bound targets
ifndef PROJECT
$(error PROJECT is required. Usage: make <target> PROJECT=<name>)
endif

CONFIG_FILE := $(HOME)/.ptekwpdev/environments.json
APP_PROJECT_BASE := $(shell jq -r '.app.project_base' $(CONFIG_FILE) | sed 's|\$$HOME|$(HOME)|')
PROJECT_BASE := $(shell jq -r ".environments[\"$(PROJECT)\"].base_dir" $(CONFIG_FILE) | sed 's|^/||')
PROJECT_NAME := $(shell jq -r ".environments[\"$(PROJECT)\"].project_name" $(CONFIG_FILE))

# Provision project scaffold
provision:
	@echo "Provisioning project: $(PROJECT_NAME)"
	@bin/provision.sh --project $(PROJECT)

# Generate dev SSL certificates + proxy configs
certs:
	@echo "Generating dev SSL certificates for project: $(PROJECT_NAME)"
	@bin/generate_certs.sh --project $(PROJECT)

# Build Docker environment
build:
	@echo "Building Docker environment for project: $(PROJECT_NAME)"
	@bin/build.sh --project $(PROJECT)

# Run WordPress auto-install inside container
autoinstall:
	@echo "Running WordPress auto-install for project: $(PROJECT_NAME)"
	@bin/autoinstall.sh --project $(PROJECT)

# Combined setup: provision + certs + build + autoinstall
setup:
	@$(MAKE) provision PROJECT=$(PROJECT)
	@$(MAKE) certs PROJECT=$(PROJECT)
	@$(MAKE) build PROJECT=$(PROJECT)
	@$(MAKE) autoinstall PROJECT=$(PROJECT)

# Clean: remove generated project folder (resolved relative to app.project_base)
clean:
	@echo "Cleaning project: $(PROJECT_NAME)"
	@rm -rf $(APP_PROJECT_BASE)/$(PROJECT_BASE)
	@echo "Removed $(APP_PROJECT_BASE)/$(PROJECT_BASE)"

# Assets: repo-neutral asset pipeline
# Example usage:
#   make assets ACTION=build
#   make assets ACTION=copy-asset TYPE=plugin NAME=myplugin VERSION=1.0 SRC=path/to.zip
assets:
	@echo "Running assets pipeline (ACTION=$(ACTION))"
	@bin/assets.sh --action $(ACTION) --type $(TYPE) --name $(NAME) --version $(VERSION) --src $(SRC)

# Allow shorthand: "make demo" → runs setup for project=demo
%:
	@$(MAKE) setup PROJECT=$@

# ---------------------------------------------------------
# Cleanup targets
# ---------------------------------------------------------

# Cleanup a single project (project-only cleanup)
clean-project:
	@echo "Cleaning project (project-only): $(PROJECT_NAME)"
	@bin/cleanup-project.sh $(PROJECT) --no-prompt

# Cleanup ALL projects (project-only cleanup)
clean-all-projects:
	@echo "Cleaning ALL projects (project-only)"
	@bin/cleanup-project.sh --all --no-prompt

# Full teardown: all projects + app-wide Docker + CONFIG_BASE
clean-all:
	@echo "Performing FULL teardown of all deployed assets"
	@bin/cleanup-all.sh --no-prompt