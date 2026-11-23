# Validation record — 2026-11-23

- PASS: local structural/resource checks (`python scripts/check-project.py`).
- PASS: JavaScript fixture integration from source load → search → details → catalog → chapter text, CSS extraction and removed audio API (`node --experimental-vm-modules scripts/test-engine.mjs`). No real third-party website used in this test.
- PASS: YAML parsing and declared target/source paths; generated icon and resource JSON.
- PASS: tree-sitter syntax checks for new application code, HTTP client, credential adapter and test files. The parser reports existing Swift 6/conditional-compilation constructs in retained upstream core; the same patterns also occur in the original files. This is not a Swift type check.
- NOT RUN: Xcode generation, Swift/C compilation, native QuickJS/Swift Testing, simulator UI, real-device installation and GitHub Actions execution (this workspace is Windows without Xcode).
- Native CI tests are included and are a required gate before packaging the unsigned IPA.
