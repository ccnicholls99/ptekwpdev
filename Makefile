PROJECT ?= default
CONFIG_FILE := $(HOME)/.ptekwpdev/environments.json
PROJECT_BASE := $(shell jq -r '.app.project_base' $(CONFIG_FILE) | sed 's|\$$HOME|$(HOME)|')
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

# Clean: remove generated project folder (uses project_name, not key)
clean:
	@echo "Cleaning project: $(PROJECT_NAME)"
	@rm -rf $(PROJECT_BASE)/$(PROJECT_NAME)
	@echo "Removed $(PROJECT_BASE)/$(PROJECT_NAME)"

# Allow shorthand: "make demo" → runs setup for project=demo
%:
	@$(MAKE) setup PROJECT=$@