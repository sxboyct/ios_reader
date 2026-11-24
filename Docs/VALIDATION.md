# Validation record — 2026-11-23

- PASS: local structural/resource checks (`python scripts/check-project.py`).
- PASS: JavaScript fixture integration from source load → search → details → catalog → chapter text, CSS extraction and removed audio API (`node --experimental-vm-modules scripts/test-engine.mjs`). No real third-party website used in this test.
- PASS: YAML parsing and declared target/source paths; generated icon and resource JSON.
- PASS: tree-sitter syntax checks for new application code, HTTP client, credential adapter and test files. The parser reports existing Swift 6/conditional-compilation constructs in retained upstream core; the same patterns also occur in the original files. This is not a Swift type check.
- NOT RUN: Xcode generation, Swift/C compilation, native QuickJS/Swift Testing, simulator UI, real-device installation and GitHub Actions execution (this workspace is Windows without Xcode).
- Native CI tests are included and are a required gate before packaging the unsigned IPA.

## 1.1.0 — Xiangse imports and custom fonts

- Skill applied: xbs-booksource-workflow, contract 2.56.1. Task is app compatibility implementation, not delivery of a new or repaired source; original input JSON remains unchanged. No site source XBS was packaged.
- Source schema: PASS (`python G:/skill/香色/scripts/check_xiangse_schema.py --strict-requestinfo G:/skill/香色/suduguu.source.json`). Editor: WARN, NEW_SCHEMA_WRAPPER medium warning (`xbs_tool.py check-editor -i` on the same input). Skill-linked tools/scripts paths were absent; existing workspace scripts supplied these checks.
- Adapter fixture tests: PASS, exact user rules with item isolation, all four steps, multi-page content merge, cycle/cross-chapter rejection, unsupported capability rejection. This is parser simulation.
- Adapter live network chain: completed via Node VM and curl native-host substitute. See xiangse-live.json for exact request URLs and counts. Not a native URLSession/QuickJS or official StandarReader run. Original source has missing catalog pagination and nonmatching introduction selector; documented in README.
- Font attachment: read-only FontTools inspection, valid sfnt with PostScript name BiLZDGLHYSS, 10575 cmap entries; attachment is not redistributed.
- Native CI tests added: XBS known independent codec vector, bad containers, JSON extension/size checks, invalid fonts, generated original font import/registration/duplicate/restore/removal, Xiangse source persistence, native dispatcher boot. These tests are NOT RUN locally (Windows, no Xcode).
- New Swift source syntax and YAML structure checked locally; syntax analysis is not compilation.
- Official StandarReader acceptance: BLOCKED — exact official unmodified 2.56.1 runtime/provenance is unavailable. iOS picker usability, font rendering, native compilation and device tests remain NOT RUN. No final skill-level pass is claimed.

## 1.2.0 — Fullscreen, page turning and iOS file import

- Removed the Font tab; retained font controls in reading settings.
- All chapter entry points now present ReaderView using fullScreenCover. Main navigation/tab UI is outside the reader presentation; status bar, home indicator and progress visibility are configurable and default hidden. Center tap reveals in-reader controls and exit.
- Added TextKit pagination and native rendering for slide, UIKit curl, cover, fade, vertical and continuous scroll modes. Text measurement and page drawing share one layout. End/start chapter transitions skip volume headings. Progress stores an optional UTF-16 characterOffset; old paragraph progress remains a migration fallback. Font/size/viewport changes retain text position.
- Replaced SwiftUI fileImporter with UIDocumentPickerViewController(forOpeningContentTypes:asCopy:true), plus folder-scoped in-app JSON/XBS listing, and app document declarations/onOpenURL. This addresses the reported disabled JSON selector through two independent import paths. Actual iPhone 17 / iOS 26.6.1 UI remains unverified.
- PASS locally: new/changed Swift syntax parsing (not type-checking), project YAML/document declarations, source/resource inventory, Legado fixture tests and Xiangse fixture tests.
- Added native tests for complete and nonoverlapping page character ranges, long paragraphs/emoji, font/viewport reflow anchors, old/new progress persistence, and provider-UTI-independent folder import followed by bounded file reading. Native tests are configured in the existing Actions test target, but NOT RUN locally.
- NOT RUN: Xcode Swift compilation, iOS Simulator/UIKit interaction tests, curl gesture/animation inspection, status-bar/home-indicator behavior, actual Files providers and iPhone installation. This Windows host has no Xcode; no successful IPA build is claimed.

Device acceptance for this version:
1. Install 1.2.0 (3); confirm only Shelf, Search, Sources tabs exist.
2. Open an existing book; confirm the tab/nav/status chrome is absent; center tap opens menu and exit returns to the prior page.
3. In each of six modes, turn forward/back, cross chapter boundaries, change font/size and reopen the book to check the saved place. Check a paragraph longer than one screen and iPad rotation.
4. Choose suduguu.json with the native file picker. If the provider disables it, select its containing folder and import it from the in-app list; repeat from Files share/open. Check cancel, empty folder, wrong file type and not-yet-downloaded cloud files.
5. Import/switch/remove a font from reading settings and check it after relaunch.


## 1.2.1 / build 4 — 2026-11-24

Changes:
- Slide mode uses a horizontal pan with two adjacent page canvases following the finger. Only release beyond 50% of the reading viewport commits; equality, shorter flicks, and cancellation return to the original page. Velocity never bypasses the threshold. Default rightward movement opens the next page, with a direction toggle in settings. Other turn modes remain separate.
- Settings use an independent solid-color overlay with a draggable header and a scrolling form. Resizing the panel does not resize/reflow the reader behind it or apply modal dimming. Font-size/spacing reflow is coalesced for 120 ms. The font screen uses the same background.
- Font import normalizes file paths before comparison, so differing base-relative/absolute URL representations cannot classify the new file as an existing duplicate. Same-name re-imports select the existing file. Failed persisted font files are exposed with a delete action. Import errors also refresh this inventory; font loading runs off the UI actor.

Local verification:
- PASS: scripts/check-project.py.
- PASS: bundled Legado engine regression (scripts/test-engine.mjs).
- PASS: Swift tree-sitter syntax parsing for the 16 App/core/test files checked. This is NOT Swift compilation or type checking.
- PASS: YAML parsing; version 1.2.1 / build 4; existing Actions workflow still includes the native test target.
- Added native tests: exact-half/over-half/cancelled/reversed-direction gesture decisions; equivalent font directory URL representations; same-name fonts with different bytes; invalid persisted font files remain visible and removable.
- NOT RUN: Swift compiler, native tests, CoreText runtime registration, simulator, IPA build, physical-device UI/performance. Windows has no swift/xcodebuild available.

Device acceptance (iPhone 17 and the user's reported iOS 26.6.1):
1. With slide mode, drag right 30%, exactly 50%, and 70%; release. The first two must return to the same page; only the third advances. Repeat leftward for the previous page, rapidly flick under half width, cancel with an interruption, reverse a drag before releasing, and toggle the reading direction.
2. Repeat at chapter edges and in the first/last chapter. Adjacent chapters load only after an accepted drag; short/cancelled drags must preserve position. Confirm tap turns, other turn modes, rotation, and disabled animations.
3. Open settings in paper/day/night themes. Drag the header repeatedly and scroll the form. The underlying page must keep its position, typography, and background. Navigate to fonts/back. Check size/spacing sliders and reopen/close settings.
4. Upgrade retaining app data. Open fonts, re-import the supplied TTF twice (including a renamed copy), select System then the imported font, and restart. A valid font must stay visible and selectable. Any unreadable/unregisterable leftover must appear under the repair section and be removable. No user font is bundled in the source archive.
