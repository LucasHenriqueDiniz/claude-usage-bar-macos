BUNDLE_ID := dev.claude-usage-bar.menubar

.PHONY: build run install uninstall clean

build:
	swift build -c release

## Run in the foreground, for hacking on it. Ctrl-C stops it.
run: build
	./.build/release/ClaudeUsageBar

install:
	./scripts/install.sh

uninstall:
	./scripts/uninstall.sh

clean:
	rm -rf .build
