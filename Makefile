.PHONY: build run release run-release clean xcode profile test format help

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

# Optimized release build + bundle. `swift build --show-bin-path` yields the exact,
# config-specific release bin dir, so the bundle path is unambiguous (unlike the debug
# target's find|head, which is ambiguous once both debug and release builds exist).
# Produces an UNSIGNED .app — code-signing + notarization is a separate downstream step.
release:
	swift build -c release -j 8
	@BIN="$$(swift build -c release --show-bin-path)"; \
		APP_BUNDLE="$$BIN/AdaptiveSound.app"; \
		python3 scripts/bundle-app.py \
			--executable "$$BIN/AdaptiveSound" \
			--output "$$APP_BUNDLE" \
			--info-plist Sources/AdaptiveSound/Info.plist \
			--icon Sources/AdaptiveSound/Assets.xcassets/AppIcon.appiconset/AppIcon.icns; \
		echo "✅ Release app bundle: $$APP_BUNDLE"; \
		echo "$$APP_BUNDLE" > /tmp/adaptive-sound-release-app-path

run-release: release
	@open "$$(cat /tmp/adaptive-sound-release-app-path)"

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
	@echo "  make build  - Build + bundle app (debug)"
	@echo "  make run    - Build and launch app (debug)"
	@echo "  make release     - Optimized release build + bundle (.build/release/AdaptiveSound.app, unsigned)"
	@echo "  make run-release - Release build + launch"
	@echo "  make clean  - Remove build artifacts"
	@echo "  make test   - Run test suite"
	@echo "  make format - Format code (Swift + C++)"
	@echo "  make profile- Build and profile with system trace"
