.PHONY: build run release run-release clean xcode profile test format library-store-verify gate sanitize tsan sanitize-library-store regenerate-metadata-fixtures help

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

# M11 (S8.3): the FFmpeg-metadata C bridge (FileDecodeSource.mm's new/delete handle + the
# std::vector art copy in readAttachedArt) under AddressSanitizer. `make sanitize`/`tsan`
# only instrument the standalone C++ null test — never this bridge — so this target builds +
# runs the library-store harness with ASan; its real-file cases (Y/Z/AC) drive
# ffmpegOpenMetadata → accessors → ffmpegCloseMetadata over the flac/m4a fixtures. Catches
# heap-overflow / use-after-free / double-free in the bridge's handle lifecycle. NOTE:
# macOS/Apple-Silicon ASan ships NO LeakSanitizer, so leaks are covered by the opaque-handle
# RAII design + review, not by this gate. Part of the pre-merge sanitizer suite (with sanitize/tsan).
sanitize-library-store:
	swift run --sanitize=address VerifyLibraryStore

# Regenerate the S8.3 metadata-extraction fixtures (Tests/Fixtures/artwork-audio/).
# DEV-ONLY + manual: the checked-in fixtures are AUTHORITATIVE and `make gate` never runs
# this (a builder need not have ffmpeg). Self-made/public-domain — a sine tone + a solid
# cover, tagged via ffmpeg. See that dir's README.md.
regenerate-metadata-fixtures:
	@dir=Tests/Fixtures/artwork-audio; mkdir -p "$$dir"; \
	ffmpeg -hide_banner -loglevel error -f lavfi -i "color=c=blue:s=64x64:d=1" -frames:v 1 -y "$$dir/cover.png"; \
	ffmpeg -hide_banner -loglevel error -f lavfi -i "sine=frequency=440:duration=0.3" -i "$$dir/cover.png" \
	  -map 0:a -map 1:v -c:a aac -c:v copy -disposition:v attached_pic \
	  -metadata title="Verify Title" -metadata artist="Verify Artist" -metadata album="Verify Album" \
	  -metadata album_artist="Verify Artist" -metadata date="2001" -metadata track="3/12" \
	  -metadata disc="1/2" -metadata genre="TestGenre" -y "$$dir/fixture.m4a"; \
	ffmpeg -hide_banner -loglevel error -f lavfi -i "sine=frequency=440:duration=0.3" -i "$$dir/cover.png" \
	  -map 0:a -map 1:v -c:a flac -c:v copy -disposition:v attached_pic \
	  -metadata title="Verify Title" -metadata artist="Verify Artist" -metadata album="Verify Album" \
	  -metadata album_artist="Verify Artist" -metadata date="2001" -metadata track="3/12" \
	  -metadata disc="1/2" -metadata genre="TestGenre" -y "$$dir/fixture.flac"; \
	ffmpeg -hide_banner -loglevel error -f lavfi -i "sine=frequency=440:duration=0.3" \
	  -map 0:a -c:a aac -map_metadata -1 -y "$$dir/no-tags.m4a"; \
	echo "cover.png sha256 (pin in ChecksMetadataReal.knownCoverSHA256 + the README table): $$(shasum -a 256 "$$dir/cover.png" | awk '{print $$1}')"; \
	rm -f "$$dir/cover.png"; \
	echo "Regenerated $$dir fixtures (fixture.m4a, fixture.flac, no-tags.m4a)."

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
	@echo "  make sanitize-library-store - VerifyLibraryStore under ASan (M11: FFmpeg-metadata bridge memory safety)"
	@echo "  make regenerate-metadata-fixtures - Rebuild the S8.3 tagged test fixtures (needs ffmpeg; manual)"
	@echo "  make profile- Build and profile with system trace"
