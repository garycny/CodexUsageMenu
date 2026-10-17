APP_DIR := apps/CodexUsageMenuBar
XCODE_DERIVED_DATA ?= .build-cache/xcode

.PHONY: build app test native-test source-archive xcode-build signing-info release-signed release clean

build:
	$(MAKE) -C "$(APP_DIR)" build

app:
	$(MAKE) -C "$(APP_DIR)" app

test:
	python3 -m unittest discover -s tests -v

native-test:
	@set -eu; \
		test_dir=$$(mktemp -d "$${TMPDIR:-/tmp/}codexusage-tests.XXXXXX"); \
		trap 'rm -rf "$$test_dir"' EXIT; \
		clang -fobjc-arc -mmacosx-version-min=13.0 tests/native_smoke.m -o "$$test_dir/native-smoke" -framework Cocoa; \
		"$$test_dir/native-smoke"

source-archive:
	python3 scripts/export_source.py

xcode-build:
	xcodebuild -project "$(APP_DIR)/CodexUsageMenuBar.xcodeproj" \
		-scheme CodexUsageMenuBar \
		-configuration Debug \
		-destination 'platform=macOS' \
		-derivedDataPath "$(XCODE_DERIVED_DATA)" \
		CODE_SIGNING_ALLOWED=NO build

signing-info:
	$(MAKE) -C "$(APP_DIR)" signing-info

release-signed:
	$(MAKE) -C "$(APP_DIR)" release-signed

release:
	$(MAKE) -C "$(APP_DIR)" release

clean:
	$(MAKE) -C "$(APP_DIR)" clean
