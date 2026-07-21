# Orbit MCP — local build / run helpers.
#
# Quick start:
#   make run     # build the app and launch it (appears in the menu bar)
#   make test    # run the unit test suite
#   make stop    # quit a running instance
#
# Output goes to ./build (gitignored). Override any variable on the command
# line, e.g. `make run CONFIG=Release`.

PROJECT  := Orbit MCP.xcodeproj
SCHEME   := Orbit MCP
CONFIG   := Debug
DERIVED  := build
APP      := $(DERIVED)/Build/Products/$(CONFIG)/Orbit MCP.app

XCODEBUILD := xcodebuild -project "$(PROJECT)" -scheme "$(SCHEME)" -configuration $(CONFIG) -destination 'platform=macOS'

.DEFAULT_GOAL := help

.PHONY: help build run stop test clean

help: ## Show this help
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) \
		| awk 'BEGIN {FS = ":.*?## "} {printf "  \033[36m%-8s\033[0m %s\n", $$1, $$2}'

build: ## Build the app into ./build
	$(XCODEBUILD) -derivedDataPath "$(DERIVED)" build

run: build ## Build and launch the app (menu bar)
	-pkill -f "Orbit MCP.app/Contents/MacOS/Orbit MCP" 2>/dev/null || true
	open "$(APP)"

stop: ## Quit a running instance
	-pkill -f "Orbit MCP.app/Contents/MacOS/Orbit MCP" 2>/dev/null || true

test: ## Run the unit test suite
	$(XCODEBUILD) -parallel-testing-enabled NO test

clean: ## Remove build output
	-$(XCODEBUILD) -derivedDataPath "$(DERIVED)" clean 2>/dev/null || true
	rm -rf "$(DERIVED)"
