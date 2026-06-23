# Omelet Pi 4 — convenience wrappers around scripts/ and the flash skill.
# Run `make` (or `make help`) to see all targets.

SHELL    := /bin/bash
FLASH    := .claude/skills/flash-pi-image-macos/scripts/flash.sh

# Flash parameters (override on the command line):
#   make flask DISK=/dev/disk4                 # newest deploy/*.wic.bz2
#   make flask DISK=/dev/disk4 IMAGE=path.wic  # explicit image
#   make flask DISK=/dev/disk4 YES=1           # skip the type-to-confirm prompt
#   SUDO_PASSWORD=… make flask DISK=/dev/disk4 YES=1   # non-interactive
DISK  ?=
IMAGE ?=
YES   ?=
FLASK_ARGS := $(if $(YES),-y) $(strip $(DISK) $(IMAGE))

.DEFAULT_GOAL := help

.PHONY: help build checkout shell deploy qemu disks flask flash

help: ## Show this help
	@echo "Omelet Pi 4 — make targets:"
	@grep -E '^[a-zA-Z_-]+:.*?## ' $(MAKEFILE_LIST) \
		| awk 'BEGIN{FS=":.*?## "}{printf "  \033[36m%-10s\033[0m %s\n", $$1, $$2}'
	@echo
	@echo "Flash usage:  make flask DISK=/dev/diskN [IMAGE=...] [YES=1]"
	@echo "Find the card with:  make disks"

build: ## Full Yocto build of omelet-image (Docker)
	./scripts/build.sh

checkout: ## Clone/checkout the Yocto layers only
	./scripts/build.sh checkout

shell: ## Interactive bitbake shell in the builder container
	./scripts/build.sh shell

deploy: ## Copy the built *.wic.bz2 out to ./deploy/
	./scripts/deploy-image.sh

qemu: ## Boot the built image in QEMU (smoke test)
	./scripts/run-qemu.sh

disks: ## List attached disks (find your SD card here)
	@diskutil list

flask flash: ## Flash an image to an SD card — needs DISK=/dev/diskN
	@if [ -z "$(DISK)" ]; then \
		echo "Usage: make flask DISK=/dev/diskN [IMAGE=...] [YES=1]"; \
		echo; echo "Attached disks:"; diskutil list; \
		exit 2; \
	fi
	$(FLASH) $(FLASK_ARGS)
