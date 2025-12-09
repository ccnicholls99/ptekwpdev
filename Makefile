# Default project key can be overridden: make certs PROJECT=demo
PROJECT ?= default

# Provision project scaffold
provision:
	@echo "Provisioning project: $(PROJECT)"
	@bin/provision.sh --project $(PROJECT)

# Generate dev SSL certificates + proxy configs
certs:
	@echo "Generating dev SSL certificates for project: $(PROJECT)"
	@bin/generate_certs.sh --project $(PROJECT)

# Combined setup: provision + certs
setup:
	@$(MAKE) provision PROJECT=$(PROJECT)
	@$(MAKE) certs PROJECT=$(PROJECT)

# Allow shorthand: "make demo" → runs setup for project=demo
%:
	@$(MAKE) setup PROJECT=$@