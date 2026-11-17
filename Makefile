VERSION := $(shell cat version.txt)
IMAGE := ghcr.io/felddy/prusa-connect
REPO := felddy/prusa-connect-container
RULESET_DIR := .github/rulesets

.PHONY: all build test lint version clean guard-gh guard-jq apply-ruleset export-ruleset

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

guard-gh:
	@command -v gh >/dev/null 2>&1 || { echo "ERROR: gh is required" >&2; exit 1; }

guard-jq:
	@command -v jq >/dev/null 2>&1 || { echo "ERROR: jq is required" >&2; exit 1; }

## apply-ruleset: create or update every ruleset in RULESET_DIR (IDs resolved by name).
apply-ruleset: guard-gh guard-jq
	@test -n "$$(ls $(RULESET_DIR)/*.json 2>/dev/null)" || { echo "ERROR: no ruleset files in $(RULESET_DIR)" >&2; exit 1; }
	@set -e; \
	for f in $(RULESET_DIR)/*.json; do \
	  name=$$(jq -r '.name' "$$f"); \
	  id=$$(gh api "repos/$(REPO)/rulesets" --jq "[.[] | select(.name == \"$$name\") | .id][0] // empty"); \
	  if [ -n "$$id" ]; then \
	    echo "Updating ruleset '$$name' (id $$id) in $(REPO)"; \
	    gh api --method PUT "repos/$(REPO)/rulesets/$$id" --input "$$f" >/dev/null; \
	  else \
	    echo "Creating ruleset '$$name' in $(REPO)"; \
	    gh api --method POST "repos/$(REPO)/rulesets" --input "$$f" >/dev/null; \
	  fi; \
	done; \
	echo "Done."

## export-ruleset: overwrite each file in RULESET_DIR from its live ruleset.
export-ruleset: guard-gh guard-jq
	@test -n "$$(ls $(RULESET_DIR)/*.json 2>/dev/null)" || { echo "ERROR: no ruleset files in $(RULESET_DIR)" >&2; exit 1; }
	@set -e; \
	for f in $(RULESET_DIR)/*.json; do \
	  name=$$(jq -r '.name' "$$f"); \
	  id=$$(gh api "repos/$(REPO)/rulesets" --jq "[.[] | select(.name == \"$$name\") | .id][0] // empty"); \
	  if [ -z "$$id" ]; then echo "ERROR: no ruleset named '$$name' in $(REPO)" >&2; exit 1; fi; \
	  raw=$$(gh api "repos/$(REPO)/rulesets/$$id"); \
	  printf '%s\n' "$$raw" | jq '{name, target, enforcement, conditions, bypass_actors, rules}' > "$$f.tmp"; \
	  mv "$$f.tmp" "$$f"; \
	  echo "Exported ruleset '$$name' to $$f"; \
	done
