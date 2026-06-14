.PHONY: build run clean open profile test

build:
	swift build -c debug
	@bash -c '\
		BUILD_DIR=".build/debug"; \
		APP_BUNDLE="$$BUILD_DIR/AdaptiveSound.app"; \
		mkdir -p "$$APP_BUNDLE/Contents/MacOS" "$$APP_BUNDLE/Contents/Resources"; \
		cp "Sources/AdaptiveSound/Info.plist" "$$APP_BUNDLE/Contents/Info.plist"; \
		cp "Sources/AdaptiveSound/Assets.xcassets/AppIcon.appiconset/AppIcon.icns" "$$APP_BUNDLE/Contents/Resources/AppIcon.icns" 2>/dev/null || true; \
		cp "$$BUILD_DIR/AdaptiveSound" "$$APP_BUNDLE/Contents/MacOS/AdaptiveSound"; \
		chmod +x "$$APP_BUNDLE/Contents/MacOS/AdaptiveSound"; \
	'

run: build
	@open .build/debug/AdaptiveSound.app

clean:
	rm -rf .build
	rm -rf .swiftpm

xcode:
	open -a Xcode .

profile:
	swift build -c debug
	open .build/debug/AdaptiveSound.app --args -com.apple.CoreFoundation.logging.level 3

test:
	swift test

format:
	swift format -i Sources/ 2>/dev/null || true
	clang-format -i Sources/AudioDSP/*.{h,cpp,mm} 2>/dev/null || true

help:
	@echo "AdaptiveSound Build Commands:"
	@echo "  make xcode  - Open in Xcode IDE (RECOMMENDED for development)"
	@echo "  make build  - Build from command line"
	@echo "  make run    - Build and run"
	@echo "  make clean  - Remove build artifacts"
	@echo "  make test   - Run tests"
	@echo "  make format - Format code"
