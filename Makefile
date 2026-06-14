.PHONY: build run clean xcode profile test format help

build:
	swift build -c debug -j 8
	@bash -c '\
		EXECUTABLE=$$(find .build -type f -name AdaptiveSound -not -path "*/.*" | head -1); \
		BUILD_DIR=$$(dirname "$$EXECUTABLE"); \
		APP_BUNDLE="$$BUILD_DIR/AdaptiveSound.app"; \
		python3 scripts/bundle-app.py \
			--executable "$$EXECUTABLE" \
			--output "$$APP_BUNDLE" \
			--info-plist Sources/AdaptiveSound/Info.plist \
			--icon Sources/AdaptiveSound/Assets.xcassets/AppIcon.appiconset/AppIcon.icns; \
		echo "✅ App bundle: $$APP_BUNDLE"; \
		echo "$$APP_BUNDLE" > /tmp/adaptive-sound-app-path; \
	'

run: build
	@APP_PATH=$$(cat /tmp/adaptive-sound-app-path); open "$$APP_PATH"

clean:
	rm -rf .build
	rm -rf .swiftpm

xcode:
	open -a Xcode .

profile: build
	@APP_PATH=$$(cat /tmp/adaptive-sound-app-path); open "$$APP_PATH" --args -com.apple.CoreFoundation.logging.level 3

test:
	swift test

format:
	swift format -i Sources/ 2>/dev/null || true
	clang-format -i Sources/AudioDSP/*.{h,cpp,mm} 2>/dev/null || true

help:
	@echo "AdaptiveSound Build Commands:"
	@echo "  make xcode  - Open in Xcode IDE (RECOMMENDED for development)"
	@echo "  make build  - Build + bundle app"
	@echo "  make run    - Build and launch app"
	@echo "  make clean  - Remove build artifacts"
	@echo "  make test   - Run test suite"
	@echo "  make format - Format code (Swift + C++)"
	@echo "  make profile- Build and profile with system trace"
