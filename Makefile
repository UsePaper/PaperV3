# Paper — build and bundle.
#
# `make build` and `make test` are the CI-style checks.
# `make app` assembles a runnable Paper.app from the SPM release build,
# because SPM alone produces a bare executable that Launch Services
# cannot associate with Markdown files.

APP := build/Paper.app
BINARY := .build/release/Paper

.PHONY: build test release app run clean

build:
	swift build

test:
	swift test

release:
	swift build -c release

app: release
	rm -rf $(APP)
	mkdir -p $(APP)/Contents/MacOS $(APP)/Contents/Resources
	cp $(BINARY) $(APP)/Contents/MacOS/Paper
	cp Support/Info.plist $(APP)/Contents/Info.plist
	cp -R .build/release/PaperV3_PaperApp.bundle $(APP)/Contents/Resources/
	install -m 755 scripts/paper $(APP)/Contents/Resources/paper
	printf 'APPL????' > $(APP)/Contents/PkgInfo
	codesign --force --sign - $(APP)
	@echo "Built $(APP)"

run: app
	open $(APP)

clean:
	rm -rf build
	swift package clean
