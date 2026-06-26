## Silenci — 빌드 / 패키징 / 배포 자동화

APP_NAME      := Silenci
BUNDLE_ID     := com.daeyoung.silenci
VERSION       := 1.0.0
BUILD_NUMBER  := 1
EXECUTABLE    := SilenciApp

DIST_DIR      := dist
APP_BUNDLE    := $(DIST_DIR)/$(APP_NAME).app
CONTENTS      := $(APP_BUNDLE)/Contents
MACOS_DIR     := $(CONTENTS)/MacOS
RESOURCES_DIR := $(CONTENTS)/Resources
MODULE_SRC    := ../silence_cutter
ICON_SRC      := Sources/Resources/AppIcon.icns

# Developer ID (코드 사이닝용 — 없으면 skip)
SIGN_IDENTITY ?=

.PHONY: all build bundle run clean dmg sign

## ── 기본 타겟: 릴리즈 빌드 + 앱 번들 ────────────────────────────────
all: bundle

## ── 릴리즈 빌드 ───────────────────────────────────────────────────────
build:
	swift build -c release

## ── 디버그 빌드 ───────────────────────────────────────────────────────
build-debug:
	swift build

## ── 앱 번들 생성 ──────────────────────────────────────────────────────
bundle: build
	@echo "▶ 앱 번들 생성: $(APP_BUNDLE)"
	@rm -rf $(APP_BUNDLE)
	@mkdir -p $(MACOS_DIR) $(RESOURCES_DIR)

	# 실행 파일 복사
	@cp .build/release/$(EXECUTABLE) $(MACOS_DIR)/$(EXECUTABLE)

	# Info.plist 복사
	@cp Info.plist $(CONTENTS)/Info.plist

	# 앱 아이콘 복사
	@if [ -f "$(ICON_SRC)" ]; then cp $(ICON_SRC) $(RESOURCES_DIR)/AppIcon.icns; fi

	# 로컬라이제이션 (.lproj) 복사 — macOS가 시스템 언어에 맞는 Localizable.strings를 찾는 위치
	@for lproj in Sources/Resources/*.lproj; do \
		cp -r "$$lproj" $(RESOURCES_DIR)/; \
	done

	# silence_cutter Python 모듈 번들에 포함
	@cp -r $(MODULE_SRC) $(RESOURCES_DIR)/silence_cutter
	@echo "✅ 번들 완료: $(APP_BUNDLE)"

## ── 코드 사이닝 (Developer ID 있을 때만) ─────────────────────────────
sign: bundle
	@if [ -n "$(SIGN_IDENTITY)" ]; then \
		echo "▶ 코드 사이닝: $(SIGN_IDENTITY)"; \
		codesign --deep --force --options runtime \
			--sign "$(SIGN_IDENTITY)" \
			--entitlements Silenci.entitlements \
			$(APP_BUNDLE); \
		echo "✅ 사이닝 완료"; \
	else \
		echo "⚠️  SIGN_IDENTITY 미설정 — 사이닝 생략"; \
		echo "   사용법: make sign SIGN_IDENTITY=\"Developer ID Application: 이름 (TEAMID)\""; \
	fi

## ── DMG 패키징 ────────────────────────────────────────────────────────
dmg: bundle
	@echo "▶ DMG 생성..."
	@mkdir -p $(DIST_DIR)
	@hdiutil create -volname "$(APP_NAME)" \
		-srcfolder $(APP_BUNDLE) \
		-ov -format UDZO \
		$(DIST_DIR)/$(APP_NAME)-$(VERSION).dmg
	@echo "✅ DMG: $(DIST_DIR)/$(APP_NAME)-$(VERSION).dmg"

## ── 디버그 빌드로 바로 실행 ───────────────────────────────────────────
run: build-debug
	@echo "▶ 실행..."
	@.build/debug/$(EXECUTABLE)

## ── 번들로 실행 ───────────────────────────────────────────────────────
run-bundle: bundle
	@open $(APP_BUNDLE)

## ── 정리 ─────────────────────────────────────────────────────────────
clean:
	@rm -rf .build $(DIST_DIR)
	@echo "✅ 정리 완료"

## ── 도움말 ───────────────────────────────────────────────────────────
help:
	@echo ""
	@echo "  make build        — 릴리즈 빌드"
	@echo "  make bundle       — .app 번들 생성 (dist/Silenci.app)"
	@echo "  make run          — 디버그 빌드 후 바로 실행"
	@echo "  make run-bundle   — 번들 빌드 후 open"
	@echo "  make sign         — 코드 사이닝 (SIGN_IDENTITY 필요)"
	@echo "  make dmg          — DMG 패키징"
	@echo "  make clean        — 빌드 결과 삭제"
	@echo ""
