.PHONY: help
.DEFAULT_GOAL: help
help: ## Print help
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(firstword $(MAKEFILE_LIST)) \
		| awk 'BEGIN {FS = ":.*?## "}; {printf "\033[36m%-28s\033[0m %s\n", $$1, $$2}'

# Get path to Makefile
VERSION ?= $(shell git describe --tags --always --dirty --match=v* 2> /dev/null || cat $(CURDIR)/.version 2> /dev/null || echo v0)
mkfile_path := $(abspath $(firstword $(MAKEFILE_LIST)))
base_dir := $(abspath $(dir $(mkfile_path)))

# Service name defined by path
SERVICE ?= $(notdir $(patsubst %/,%,$(dir $(mkfile_path))))
# Prefix for private repos that should not use the module mirror or checksum db
# https://golang.org/cmd/go/#hdr-Module_configuration_for_non_public_modules
GOPRIVATE ?= github.com/utilitywarehouse

# clean
.PHONY: clean
clean: ## Remove built binary
	rm -f $(SERVICE)

.PHONY: generate
generate:
	go get -u github.com/golang/mock/mockgen
	go generate ./...

# proto
.PHONY: proto
proto: ## Generate code from proto files
	./proto/gen.sh

# lint
LINTER_EXE := golangci-lint
LINTER := $(GOPATH)/bin/$(LINTER_EXE)
LINT_FLAGS ?= -j 2
LINT_RUN_FLAGS ?= -c .golangci.yml
$(LINTER):
	curl -sfL https://raw.githubusercontent.com/golangci/golangci-lint/master/install.sh| sh -s -- -b $(GOPATH)/bin v1.21.0
.PHONY: go-lint
go-lint: $(LINTER)
	$(LINTER) $(LINT_FLAGS) run $(LINT_RUN_FLAGS)

.PHONY: lint
lint: go-lint  ## Run Go and protos linters - can specify LINT_FLAGS and/or LINT_RUN_FLAGS for Go linter

# test
TEST_FLAGS := -v -cover
.PHONY: test
test: ## Run tests
	$(BUILDENV) go test $(TEST_FLAGS) ./...

# build
BUILDENV := CGO_ENABLED=0 GOPRIVATE=$(GOPRIVATE)
GIT_HASH := $(CIRCLE_SHA1)
ifeq ($(GIT_HASH),)
  GIT_HASH := $(VERSION)
endif
LINKFLAGS := -s -X main.gitHash=$(GIT_HASH) -extldflags "-static"
$(SERVICE): clean
	$(BUILDENV) go build -o $(SERVICE) -a -ldflags '$(LINKFLAGS)' ./cmd/$(SERVICE)
build: $(SERVICE) ## Build binary

.PHONY: all
all: clean generate lint test proto build ## Remove old binary, run linter, run tests and build binary

# docker - local and for CI
DOCKER_REGISTRY?=registry.uw.systems
DOCKER_REPOSITORY_NAMESPACE?=cashbackcard
DOCKER_ID?=cbc
DOCKER_REPOSITORY_IMAGE=$(SERVICE)
DOCKER_REPOSITORY=$(DOCKER_REGISTRY)/$(DOCKER_REPOSITORY_NAMESPACE)/$(DOCKER_REPOSITORY_IMAGE)

local-docker-build: ## Build docker image with local tag
	docker build -t $(DOCKER_REPOSITORY):local . --build-arg SERVICE=$(SERVICE) --build-arg GITHUB_TOKEN=$(GITHUB_TOKEN)

ci-docker-auth:
	@echo "Logging in to $(DOCKER_REGISTRY) as $(DOCKER_ID)"
	@docker login -u $(DOCKER_ID) -p $(DOCKER_PASSWORD) $(DOCKER_REGISTRY)

ci-docker-build: ci-docker-auth
	docker build --no-cache -t $(DOCKER_REPOSITORY):$(GIT_HASH)$(CIRCLE_BUILD_NUM) . --build-arg SERVICE=$(SERVICE) --build-arg GITHUB_TOKEN=$(GITHUB_TOKEN)
	docker tag $(DOCKER_REPOSITORY):$(GIT_HASH)$(CIRCLE_BUILD_NUM) $(DOCKER_REPOSITORY):latest
	docker push $(DOCKER_REPOSITORY):$(GIT_HASH)$(CIRCLE_BUILD_NUM)
	docker push $(DOCKER_REPOSITORY):latest

# kubernetes - for CI
K8S_NAMESPACE=$(DOCKER_REPOSITORY_NAMESPACE)
K8S_DEPLOYMENT_NAME=$(DOCKER_REPOSITORY_IMAGE)
K8S_CONTAINER_NAME=$(K8S_DEPLOYMENT_NAME)

K8S_URL=https://elb.master.k8s.dev.uw.systems/apis/apps/v1/namespaces/$(K8S_NAMESPACE)/deployments/$(K8S_DEPLOYMENT_NAME)
K8S_PAYLOAD={"spec":{"template":{"spec":{"containers":[{"name":"$(K8S_CONTAINER_NAME)","image":"$(DOCKER_REPOSITORY):$(GIT_HASH)$(CIRCLE_BUILD_NUM)"}]}}}}

ci-kubernetes-push:
	test "$(shell curl -o /dev/null -w '%{http_code}' -s -X PATCH -k -d '$(K8S_PAYLOAD)' -H 'Content-Type: application/strategic-merge-patch+json' -H 'Authorization: Bearer $(K8S_DEV_TOKEN)' '$(K8S_URL)')" -eq "200"
