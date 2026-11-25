# Validation record

## 1.3.6 / build 11 — 2026-11-25

- Baseline: before edits, local files matched every entry in `YingxiaReader-iOS-1.3.5-source.zip`. Preserve 1.3.5 content prefetch/memory caching, ordinary book-detail catalog, highlighted in-reader catalog and menu access during loading.
- Confirmed old backward path: slide target -1 and curl's first-page observer called boundary(false), which called jump/load/reflow and enabled the chapter preparation overlay. Previous chapters had no prepared renderer or native animation bridge. Add symmetric previous chapter layout/renderer/loading/adoption and retain the chapter just left for reverse turns.
- Separate neighboring preparation tasks from current layout application; reuse the currently applied prepared chapter when content, settings and requested position already match. Explicit chapter selections can adopt an already rendered matching target without toggling loading. Normal first-to-second-page turns keep the same layout/renderer and do not call a chapter boundary.
- Static review did not reproduce a correctly directed, within-chapter slide triggering boundary in 1.3.5; do not claim the exact device cause of that report has been measured. The added native test exercises first-page backward/forward transitions and then page two across slide/curl/cover, requiring zero fallback boundary calls and a retained curl controller.
- Added reverse native preview/return queries and slide cancellation checks. Adjacent preparation completing during a same-chapter gesture does not invalidate that gesture. Current-configuration/index checks prevent a distant cached chapter from becoming a neighbor after a catalog jump.
- Local project/resource checks, engine fixtures, Swift syntax parsing and YAML validation pass. No Xcode compiler, native test execution, IPA build or device frame timing is available on this Windows host. Actions continues to run native tests before packaging.
- Device acceptance: for multiple consecutive chapters, immediately slide from page one to page two in both configured slide directions; in curl/cover turn from page one back to the preceding chapter's last page and return. Repeat after a directory jump, with cancellation, and with an uncached previous chapter. Prepared transitions must not show the whole-chapter loading overlay; actual missing content may still need preparation.

## 1.3.4 / build 9 — 2026-11-25

- Forward chapter boundaries now provide the prepared next chapter's opening image to slide/cover animations and the native curl data source. Only a completed transition adopts the chapter; cancellation retains the old position. Adoption keeps the controller and prepared layout instead of restarting load/reflow. The next chapter is prepared through a shared task, and a boundary request can await it before animating.
- Frame/style/configuration changes invalidate obsolete transitions. Changes to a next-chapter preview cancel a transition only when it actually targets that preview; ordinary first-to-second-page turns continue when background preloading completes. Page commits reject out-of-range indices.
- Render configuration compares the stable theme/dark-mode identity, not newly bridged UIColor objects. Already applied configurations do not reflow the current chapter. This removes a potential source of delayed resets; on-device frame timing remains unmeasured.
- Reading and book-detail catalogs position the saved/current chapter in view and highlight it with a reading label. Added explicit current-chapter reload. Xiangse rejects an empty page anywhere in the content chain; existing cached files are not erased automatically.
- Native regression tests now drive slide drag/change/end/cancel handlers across a chapter boundary and into page two, introduce newly prepared neighboring content during a drag, retain the curl controller, and exercise delayed next-chapter preparation. These run in Actions; they are not executed locally on Windows.
- Local structure/resource, Legado/Xiangse fixtures and Swift syntax checks are available. Syntax parsing is not type checking. No new IPA build or physical-device smoothness result is claimed.
- Source investigation is recorded separately in `suduguu-1.3.4-investigation.json`. The unchanged attachment matches the existing fixture. A sampled four-webpage chapter merged exactly; the supplied source has no catalog continuation rule, so catalogs over the first page can remain incomplete. This source-rule limitation is separate from per-screen text pagination and from highlighting the current entry.
- Follow-up for the user's book is in `suduguu-chapter-187.json`, reproducible with `scripts/inspect-suduguu.mjs`. The website names its unique matching result 公考捡漏：从女友抛弃到权利巅峰 (`/3560/`), whereas the user wrote 权力. Chapters 186–188 each span four webpages. Chapter 187 returned 43 paragraphs / 2068 UTF-16 characters with exact ordered merge and no nested-text loss; adjacent chapter links matched the catalog. This is a network/parser check, not iOS rendering proof. The slide/curl/cover boundary test uses synthetic text with the same 43 paragraph lengths and the system font; no chapter prose is bundled.


## 1.3.3 / build 8 — 2026-11-25

- Supplied diagnostics contain no compiler `error:` lines. The simulator ran 40 tests; one rendering test produced 16 issues and stopped the workflow before device packaging. Fifteen issues compare raster pixels; another compares the rounded 273 × 446 image with a 272.5 × 445.5 point viewport at scale 1.
- Inspection of the first failed pixel arrays found 718 differing channels on the last pixel column/row. The reference filled only fractional bounds, leaving partial edge coverage. Fill the entire rounded bitmap in both the background and independent reference, and assert rounded image dimensions. Preserve exact pixel equality; report a boolean mismatch with a page number instead of dumping megabytes of pixel arrays.
- Start neighboring-page preparation immediately, independently of a pending turn. Keep the rendered target image alive through the transition rather than looking it up again after cache eviction. Curl data-source requests return only prepared images. Position translated canvases through bounds/center and avoid resizing the curl container mid-animation.
- Explicitly use TextKit 1 for the scrolling text view and finish layout before restoring a character position, so the bottom clamp uses the complete chapter height.
- Add Xcode-only application controller tests for slide/cover/vertical/fade/curl forward and reverse sequences, complete visible page labels, image availability, one commit per turn and scroll restoration to a long chapter's end. SwiftPM core tests remain independent of App sources.
- Local project/resource checks, offline engine tests and Swift syntax parsing pass. Native tests, IPA packaging and device frame-time/gesture verification have NOT been run in this Windows environment. The supplied log demonstrates execution of the previous build, not success of this revision.
- After the new Actions run passes, verify short drags, rapid repeated turns, reversed/cancelled drags, curl gestures, chapter boundaries and scrolling with the reported book/font. The controller tests exercise programmatic animated turns; they do not replace real gesture/performance testing.

## 1.3.2 / build 7 — 2026-11-25

Changes for chapter-transition stalls and incomplete later pages:
- Replaced mutable TextKit pagination containers with immutable CoreText frames. Each next page begins at the end of the preceding frame's actually visible UTF-16 range; drawing reuses that exact frame rather than laying out again. A complete, contiguous range covering the final character is required before displaying a chapter.
- Moved script conversion, chapter typesetting, background rasterization and page-image rendering off the main actor. A per-layout serial executor confines CoreText frame creation and use; the bounded image cache is lock-protected. UIKit transitions only read prepared images and request missing images asynchronously.
- Prepares the next chapter's layout and opening pages, not only its network content. Chapter changes bypass the settings debounce. While a chapter is preparing, the old page remains visible with a preparation indicator and cannot turn.
- Chapter/revision/layout identity checks discard stale load results and callbacks. A new layout and matching renderer are published together; pending turns are invalidated when the surface changes or is removed. Reflow preserves the stored character anchor.
- Retains 1.3.1 full-screen backgrounds/transitions, background deletion, panel gestures and the existing Intel Actions workflow. Bundle identifier and unsigned artifact names are unchanged.

Local verification:
- PASS: `python scripts/check-project.py`.
- PASS: `node --experimental-vm-modules scripts/test-engine.mjs`.
- PASS: `node --experimental-vm-modules scripts/test-xiangse.mjs` (offline fixtures).
- PASS: tree-sitter syntax parsing for 26 App/reader-core/reader-test Swift files. This is not Swift compilation, type checking or execution of the native tests.
- PASS: project/workflow YAML; version 1.3.2 / build 7; existing simulator-test/device-build/unsigned-package workflow retained.
- Added native tests for consecutive chapters, long paragraphs, empty paragraphs, emoji/combining characters, large fonts, visible CoreText ranges and full character reconstruction. Rendering tests compare every page against independently created reference frames, revisit pages after eviction, check worker execution, cache bounds and chapter image isolation.
- NOT RUN: native Swift tests, Xcode compilation, simulator/device testing, frame-time profiling, remote Actions or IPA packaging. This environment is Windows without Xcode. No measured device smoothness or successful IPA build is claimed.

Required acceptance after Actions passes:
1. Open the reported tenth chapter, turn from page 1 to page 2 immediately, then continue through its final page into chapter 11 and turn several more pages. Repeat with cached content/offline so network time is excluded; check for dropped touches and freezes.
2. Compare the last sentences of each page with the first sentences of the next page and with the source chapter, especially the second page and the chapter's final sentence. Check no missing, duplicated or blank text. Repeat backward through the boundary.
3. Repeat with the imported font, largest available font/line spacing, long single paragraphs and portrait/landscape rotation. Change font/rotation while preparing a chapter and rapidly switch chapters; verify stale pages do not replace the selected chapter.
4. Verify progress restoration after exit/background, all turn styles, full-screen image backgrounds and deletion, and upward/downward settings-panel drags. Profile device frame times if a stall remains; include chapter/source, font and turn style when reporting it.

## 1.3.1 / build 6 — 2026-11-24

Changes following the device screenshot:
- Full-screen viewport dimensions include safe-area insets. Only the text container is inset; backgrounds and every translated/faded/curled page occupy the complete viewport. Scroll mode retains a safe-area text frame over the full-screen backdrop.
- Moved the reflow task from the conditional content group to a stable container and replaced chapter-value task identity with a content revision UUID. A loading-to-reader transition no longer starts a second layout task for the same chapter.
- Added a shared opaque background raster and a bounded three-page render cache. The current and adjacent pages are prepared before the new chapter's page surface is shown; subsequent cache warming is cancelled during gestures and delayed until after a completed turn. Unchanged reader updates do not redraw the background.
- Moved shelf JSON encoding and writing to a serial background queue. Exit/background events flush outstanding writes so queued progress is not intentionally left pending at suspension.
- The first reading-settings section has a persistent visible delete-background button beside photo selection. It removes the app's saved image and restores the theme without modifying the original photo.
- Expanded settings accept downward drags from the whole panel. A scrolled list returns to its top before the continuing drag resizes the panel; upward scrolling and horizontal sliders remain separate.
- Preserved the Intel Actions runner, bundle identifier and unsigned IPA packaging.

Validation:
- PASS: project/resource checks and offline Legado/Xiangse engine regressions.
- PASS: local Swift syntax parsing; project/workflow YAML and version checks. Syntax parsing is not Swift compilation or type checking.
- Added native regression cases for portrait/landscape safe-area geometry, full-screen image coverage at all four corners, cached-image identity/three-page memory bounds, and list-scroll-to-panel-drag handoff.
- NOT RUN locally: Xcode compilation, native tests, simulator/device rendering, frame-time profiling and IPA packaging. Windows has no Xcode. Device smoothness is not claimed as measured.

Required checks after Actions builds successfully:
1. On the device from the screenshot, verify the photo and moving page reach all four screen edges, while text avoids the camera/home areas. Repeat with no photo, rotation, each turn style and Reduce Motion.
2. Enter a new chapter and immediately flip several pages forward/back. Verify no delayed layout reset, page jump or dropped progress. Repeat with a long chapter, imported font and large photo.
3. Open settings and confirm red 删除背景图 is visible at the top. Delete, restart, and verify the image stays removed; import another photo and repeat.
4. Expand settings, drag down from the title/blank space/list row, then scroll the list away from its top and drag back to the top and onward. Confirm both scroll and resize work without needing the handle.
5. Exit/reopen and background/relaunch after a turn. Confirm the last stored character offset and existing library/fonts remain intact.

## 1.3.0 / build 5 — 2026-11-24

Runner queue follow-up:
- Public repository run #5 reported: "There is no available hosted runner capacity for the selected runner type right now." Its runner type was macOS 26 ARM64. This failed before any checkout/test/build step.
- Changed the local workflow label from `macos-26` to `macos-26-intel`, retaining the iOS test/build/package steps. This selects the standard Intel pool rather than the affected ARM pool; it does not guarantee immediate runner availability.
- Commit the workflow change and start a new workflow_dispatch run. Re-running an old run continues to reference its original workflow commit.
- No successful remote Xcode build is claimed for this change.

Current changes (supersede the historical gesture/import checklists below):
- Display name is 映夏阅读. Bundle ID, scheme, Actions workflow and unsigned IPA artifact names are unchanged.
- Slide turns retain the finger-following animation and settle animation. Release commits at 12% of viewport width, capped at 40 points, or after an aligned 450-point/second flick with at least 8 points of travel. Cancellation does not commit.
- A UIKit pan recognizer covers the complete compact settings panel. An upward drag of 24 points, or its projected flick distance, expands it. Horizontal gestures remain available for sliders; the expanded form scrolls normally, and the handle can collapse it. The reader viewport stays unchanged.
- Photo backgrounds are imported with PhotosPicker, normalized to PNG with orientation correction and a 2048-pixel longest edge, and stored locally. Selection, replacement, removal, restart restoration and opacity control are included. All page canvases and the scrolling backdrop use the same image without reflowing text.
- Removed the folder import UI; retained copy-based JSON/XBS file import and Files app open/share handling. Source parsing is unchanged.
- Search history persists 30 trimmed, deduplicated terms in most-recent-first order, supports tapping to search, individual deletion and confirmed clearing.

Local verification:
- PASS: `python scripts/check-project.py`.
- PASS: `node --experimental-vm-modules scripts/test-engine.mjs`.
- PASS: `node --experimental-vm-modules scripts/test-xiangse.mjs` (offline fixtures).
- PASS: Swift tree-sitter syntax parsing for 14 App/core/test files. This is NOT Swift compilation or type checking.
- PASS: YAML parsing; name/version/build and unchanged bundle ID; Actions still runs simulator tests before device build and unsigned IPA packaging.
- Native tests updated/added for short drags, flick direction/noise/cancellation, history deduplication/limits/serialization/deletion, and background downsampling/persistence/removal/invalid or oversized input.
- NOT RUN: Swift/C compilation, native tests, simulator, real-device gestures/photos, remote Actions, IPA build. This environment is Windows without Xcode.

Required device acceptance after a successful Actions run:
1. In slide mode, drag about 40 points in both directions and release: retain the translation animation and commit once. Also try a short fast flick, a tiny slow drag, cancellation, direction reversal, both reading directions, chapter boundaries and Reduce Motion.
2. Open settings and pull upward from a blank area, a form row, the navigation title and a slider row; the compact panel must expand without moving the reader's text. Check horizontal sliders, expanded form scrolling and handle collapse, including the font screen.
3. Select portrait/landscape and cloud-backed photos, adjust opacity in light/dark themes, turn pages in every style, restart, replace and remove the image. Cancellation and failed selection must leave the previous background intact.
4. Import JSON/XBS through the file selector and Files share/open; verify no folder import entry remains.
5. Search trimmed/repeated keywords, tap history, restart, remove an entry and cancel/confirm clear. Check that history does not push down active search results.
6. Upgrade in place: verify the home-screen label is 映夏阅读 and existing shelf, fonts and reading positions remain available.

## Initial validation — 2026-11-23

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
## 1.3.5 / build 10 — 2026-11-25

- Investigation: existing chapter files already prevent repeat network requests, but the two-chapter `NovelBooks.prefetch` helper had no caller. ReaderView only prepared one following chapter; explicit chapter selection did not join its unfinished preparation. Full-surface hit testing and the UIKit gesture delegate both suppressed menu taps during loading.
- Wire prefetch to each loaded chapter, skip arbitrary runs of volume headings, stop scheduling when the view task is cancelled, and reuse in-flight content requests. Add a six-entry LRU memory cache before disk decoding. Manual reload bypasses cache and waits out an older speculative request before fetching anew. Join the next-chapter preparation on explicit selection, and avoid rewarming an already rendered target page.
- Restore BookDetailView's ordinary list without automatic positioning or highlighting. ReaderView's in-reader directory retains both features. Permit menu taps during loading; keep page-turn guards and stale-result checks.
- Added native tests for the next two readable indices, offline prefetch into memory, cache invalidation, and menu availability during a delayed next-chapter load. These require the existing Xcode workflow and have NOT been executed on Windows.
- Local project/resource checks and offline Legado engine tests pass. Tree-sitter inspection of 48 Swift files has no new error nodes relative to 1.3.4; the grammar still reports existing limitations in three core files. This is not type checking, a successful IPA build, or a measured device performance result.

