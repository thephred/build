ifeq ($(HELM_CHARTS),)
$(error the variable HELM_CHARTS must be set prior to including helm.mk)
endif

# the base url where helm charts are published
ifeq ($(HELM_BASE_URL),)
$(error the variable HELM_BASE_URL must be set prior to including helm.mk)
endif

# the s3 bucket where helm charts are published
ifeq ($(HELM_S3_BUCKET),)
$(error the variable HELM_S3_BUCKET must be set prior to including helm.mk)
endif

# the charts directory
HELM_CHARTS_DIR ?= $(ROOT_DIR)/cluster/charts

# the charts output directory
HELM_OUTPUT_DIR ?= $(OUTPUT_DIR)/charts

# the helm index file
HELM_INDEX := $(HELM_OUTPUT_DIR)/index.yaml

# helm home
HELM_HOME := $(abspath $(WORK_DIR)/helm)
export HELM_HOME

# helm tool version
HELM_VERSION := v2.9.1
HELM := $(TOOLS_HOST_DIR)/helm-$(HELM_VERSION)

# remove the leading `v` for helm chart versions
HELM_CHART_VERSION := $(VERSION:v%=%)

# ====================================================================================
# Helm Targets

$(HELM_HOME): $(HELM)
	@mkdir -p $(HELM_HOME)
	@$(HELM) init -c

$(HELM_OUTPUT_DIR):
	@mkdir -p $(HELM_OUTPUT_DIR)

define helm.chart
$(HELM_OUTPUT_DIR)/$(1)-$(HELM_CHART_VERSION).tgz: $(HELM_HOME) $(HELM_OUTPUT_DIR) $(shell find $(HELM_CHARTS_DIR)/$(1) -type f)
	@$(INFO) helm package $(1) $(HELM_CHART_VERSION)
	@$(HELM) package --version $(HELM_CHART_VERSION) --app-version $(HELM_CHART_VERSION) -d $(HELM_OUTPUT_DIR) $(abspath $(HELM_CHARTS_DIR)/$(1))
	@$(OK) helm package $(1) $(HELM_CHART_VERSION)

helm.prepare.$(1): $(HELM_HOME)
	@cp -f $(HELM_CHARTS_DIR)/$(1)/values.yaml.tmpl $(HELM_CHARTS_DIR)/$(1)/values.yaml
	@cd $(HELM_CHARTS_DIR)/$(1) && $(SED_CMD) 's|%%VERSION%%|$(VERSION)|g' values.yaml

helm.prepare: helm.prepare.$(1)

helm.lint.$(1): $(HELM_HOME)
	@rm -rf $(abspath $(HELM_CHARTS_DIR)/$(1)/charts)
	@$(HELM) lint $(abspath $(HELM_CHARTS_DIR)/$(1)) $(HELM_CHART_LINT_ARGS_$(1)) --strict

helm.lint: helm.lint.$(1)

helm.dep.$(1): $(HELM_HOME)
	@$(INFO) helm dep $(1) $(HELM_CHART_VERSION)
	@$(HELM) dependency update $(abspath $(HELM_CHARTS_DIR)/$(1))
	@$(OK) helm dep $(1) $(HELM_CHART_VERSION)

helm.dep: helm.dep.$(1)

$(HELM_INDEX): $(HELM_OUTPUT_DIR)/$(1)-$(HELM_CHART_VERSION).tgz
endef
$(foreach p,$(HELM_CHARTS),$(eval $(call helm.chart,$(p))))

$(HELM_INDEX): $(HELM_HOME) $(HELM_OUTPUT_DIR)
	@$(INFO) helm index
	@$(HELM) repo index $(HELM_OUTPUT_DIR)
	@$(OK) helm index

helm.build: $(HELM_INDEX)

helm.clean: 
	@rm -fr $(HELM_OUTPUT_DIR)

# ====================================================================================
# helm

HELM_TEMP := $(shell mktemp -d)
HELM_URL := $(HELM_BASE_URL)/$(CHANNEL)

helm.promote: $(HELM_HOME)
	@$(INFO) promoting helm charts
#	copy existing charts to a temp dir, the combine with new charts, reindex, and upload
	@$(S3_SYNC) s3://$(HELM_S3_BUCKET)/$(CHANNEL) $(HELM_TEMP)
	@$(S3_SYNC) s3://$(S3_BUCKET)/build/$(BRANCH_NAME)/$(VERSION)/charts $(HELM_TEMP)
	@$(HELM) repo index --url $(HELM_URL) $(HELM_TEMP)
	@$(S3_SYNC_DEL) $(HELM_TEMP) s3://$(HELM_S3_BUCKET)/$(CHANNEL)
	@rm -fr $(HELM_TEMP)
	@$(OK) promoting helm charts

# ====================================================================================
# Common Targets

build.init: helm.prepare helm.lint
build.check: helm.dep
build.artifacts: helm.build
clean: helm.clean
lint: helm.lint
promote.artifacts: helm.promote

# ====================================================================================
# Special Targets

dep: helm.dep

define HELM_HELPTEXT
Helm Targets:
    dep          Build and publish final releasable artifacts

endef
export HELM_HELPTEXT

helm.help:
	@echo "$$HELM_HELPTEXT"

help-special: helm.help

# ====================================================================================
# Tools install targets

$(HELM):
	@$(INFO) installing helm $(HOSTOS)-$(HOSTARCH)
	@mkdir -p $(TOOLS_HOST_DIR)/tmp-helm
	@curl -fsSL https://storage.googleapis.com/kubernetes-helm/helm-$(HELM_VERSION)-$(HOSTOS)-$(HOSTARCH).tar.gz | tar -xz -C $(TOOLS_HOST_DIR)/tmp-helm
	@mv $(TOOLS_HOST_DIR)/tmp-helm/$(HOSTOS)-$(HOSTARCH)/helm $(HELM)
	@rm -fr $(TOOLS_HOST_DIR)/tmp-helm
	@$(OK) installing helm $(HOSTOS)-$(HOSTARCH)