# Makefile for AirPods Max Mute
# Provides build targets when xcodegen is available or using xcodebuild

PROJECT_NAME = AirPodsMaxMute
BUILD_DIR = build
CONFIGURATION = Debug

# Check for xcodegen
XCODEGEN := $(shell command -v xcodegen 2> /dev/null)

.PHONY: all generate build run clean install-xcodegen help

all: build

# Generate Xcode project using xcodegen
generate:
ifdef XCODEGEN
	@echo "Generating Xcode project with xcodegen..."
	xcodegen generate
	@echo "Project generated: $(PROJECT_NAME).xcodeproj"
else
	@echo "Error: xcodegen not found. Install it with: brew install xcodegen"
	@echo "Or create the Xcode project manually (see README.md)"
	@exit 1
endif

# Build the application
build: generate
	@echo "Building $(PROJECT_NAME)..."
	xcodebuild -project $(PROJECT_NAME).xcodeproj \
		-scheme $(PROJECT_NAME) \
		-configuration $(CONFIGURATION) \
		-derivedDataPath $(BUILD_DIR) \
		build

# Build release version
release: generate
	@echo "Building $(PROJECT_NAME) (Release)..."
	xcodebuild -project $(PROJECT_NAME).xcodeproj \
		-scheme $(PROJECT_NAME) \
		-configuration Release \
		-derivedDataPath $(BUILD_DIR) \
		build

# Run the application
run: build
	@echo "Running $(PROJECT_NAME)..."
	open $(BUILD_DIR)/Build/Products/$(CONFIGURATION)/$(PROJECT_NAME).app

# Clean build artifacts
clean:
	@echo "Cleaning..."
	rm -rf $(BUILD_DIR)
	rm -rf $(PROJECT_NAME).xcodeproj

# Install xcodegen via Homebrew
install-xcodegen:
	@echo "Installing xcodegen..."
	brew install xcodegen

# Open project in Xcode
open-xcode: generate
	open $(PROJECT_NAME).xcodeproj

# Help
help:
	@echo "AirPods Max Mute - Build Commands"
	@echo ""
	@echo "Usage: make [target]"
	@echo ""
	@echo "Targets:"
	@echo "  generate        Generate Xcode project from project.yml"
	@echo "  build           Build debug version"
	@echo "  release         Build release version"
	@echo "  run             Build and run the app"
	@echo "  clean           Remove build artifacts"
	@echo "  open-xcode      Open project in Xcode"
	@echo "  install-xcodegen Install xcodegen via Homebrew"
	@echo "  help            Show this help message"
	@echo ""
	@echo "Requirements:"
	@echo "  - Xcode 15.0+"
	@echo "  - macOS 14.0+"
	@echo "  - xcodegen (brew install xcodegen)"
