.PHONY: build run release run-release clean xcode profile test format library-store-verify gate sanitize tsan help

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

# S8.1a store acceptance gate — headless verification of the persistent library
# store (open/create/migrate, v1 schema, transactional + downgrade-guarded
# migration runner, corruption quarantine + rebuild, restart durability). `swift
# test` is broken here, so this executable IS the verification. Temp DBs are
# written under test-data/ (never /tmp) and cleaned up on success.
library-store-verify:
	swift run VerifyLibraryStore

# Full pre-merge gate (NOT the fast lint-only pre-commit hook): the C++ DSP null
# test (golden master), the AU-graph offline integration check, and the library
# store acceptance check. Any failure stops the chain (&&). Run before merging.
gate:
	bash scripts/build-null-test.sh && swift run VerifyAUGraph && swift run VerifyLibraryStore

# Runtime-instrumented C++ DSP null test. sanitize = AddressSanitizer + Undefined
# Behavior Sanitizer (heap/stack overruns, use-after-free, signed overflow, bad
# casts, misaligned loads in the biquad/vDSP math). tsan = ThreadSanitizer (data
# races). Both halt on the first finding with a non-zero exit. Run before merging
# changes to the AudioDSP kernels.
sanitize:
	bash scripts/build-null-test.sh --sanitize

tsan:
	bash scripts/build-null-test.sh --tsan

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
	@echo "  make library-store-verify - Run the S8.1a library-store acceptance gate"
	@echo "  make gate   - Full pre-merge gate (null test + VerifyAUGraph + VerifyLibraryStore)"
	@echo "  make sanitize - Null test under AddressSanitizer + UBSan (runtime memory/UB check)"
	@echo "  make tsan   - Null test under ThreadSanitizer (data-race check)"
	@echo "  make profile- Build and profile with system trace"
