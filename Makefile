VERSION := $(shell cat version.txt)
IMAGE := ghcr.io/felddy/prusa-connect

.PHONY: all build test lint version clean

all: build test

# Build the image for the host platform, tagged the way the tests expect.
build:
	docker build \
	  --build-arg CONTAINER_VERSION=$(VERSION) \
	  --tag $(IMAGE):$(VERSION) \
	  .

test:
	uv run --group test pytest tests/ --image-tag $(IMAGE):$(VERSION)

lint:
	uv run --group test pre-commit run --all-files

version:
	@echo $(VERSION)

clean:
	docker image rm --force $(IMAGE):$(VERSION)
