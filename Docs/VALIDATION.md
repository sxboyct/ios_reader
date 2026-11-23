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
