# Reader-only iOS derivative

- Keep this derivative scoped to Legado text reading on iPhone and iPad.
- Do not add video, music, manga, cloud drives, JVM, Node runtime, macOS or tvOS targets.
- Preserve GPL-3.0-only licensing and dependency notices.
- Run `python3 scripts/check-project.py` and `node --experimental-vm-modules scripts/test-engine.mjs`.
- Swift compilation and native tests require macOS/Xcode; use `.github/workflows/build-ios.yml`.
- Never claim a successful IPA build without a successful Xcode run. The default IPA is unsigned.
