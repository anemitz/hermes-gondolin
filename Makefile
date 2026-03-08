SHELL := /bin/bash

STACK_DIR ?= $(CURDIR)
IMAGE ?= hermes-gondolin:latest
COLIMA_PROFILE ?= hermes

.PHONY: help init build up shell down restart status clean nuke

help:
	@echo "Targets:"
	@echo "  make init    - create stack dirs/files in $(STACK_DIR)"
	@echo "  make build   - build Hermes image ($(IMAGE))"
	@echo "  make up      - init + build + launch Hermes shell"
	@echo "  make shell   - launch Hermes shell (after init/build)"
	@echo "  make down    - stop Colima profile"
	@echo "  make restart - restart Colima profile"
	@echo "  make status  - show Colima/docker status"
	@echo "  make clean   - remove Docker image"
	@echo "  make nuke    - delete Colima profile (destructive)"

init:
	STACK_DIR="$(STACK_DIR)" COLIMA_PROFILE="$(COLIMA_PROFILE)" IMAGE="$(IMAGE)" ./run-hermes.sh init

build:
	STACK_DIR="$(STACK_DIR)" COLIMA_PROFILE="$(COLIMA_PROFILE)" IMAGE="$(IMAGE)" ./run-hermes.sh build

up: init build
	STACK_DIR="$(STACK_DIR)" COLIMA_PROFILE="$(COLIMA_PROFILE)" IMAGE="$(IMAGE)" ./run-hermes.sh shell

shell:
	STACK_DIR="$(STACK_DIR)" COLIMA_PROFILE="$(COLIMA_PROFILE)" IMAGE="$(IMAGE)" HERMES_SESSION="$(filter-out $@,$(MAKECMDGOALS))" ./run-hermes.sh shell

%:
	@:

down:
	STACK_DIR="$(STACK_DIR)" COLIMA_PROFILE="$(COLIMA_PROFILE)" IMAGE="$(IMAGE)" ./run-hermes.sh down

restart:
	STACK_DIR="$(STACK_DIR)" COLIMA_PROFILE="$(COLIMA_PROFILE)" IMAGE="$(IMAGE)" ./run-hermes.sh restart

status:
	STACK_DIR="$(STACK_DIR)" COLIMA_PROFILE="$(COLIMA_PROFILE)" IMAGE="$(IMAGE)" ./run-hermes.sh status

clean:
	docker image rm -f "$(IMAGE)" || true

nuke:
	colima delete --profile "$(COLIMA_PROFILE)" --force
