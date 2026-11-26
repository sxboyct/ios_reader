"""Dependency/resource checks. This is not a replacement for Xcode compilation."""
from pathlib import Path
import json
import re

root = Path(__file__).resolve().parents[1]
for name in ['Package.swift', 'project.yml', 'LICENSE', 'App/ReaderApp.swift',
             'Vendor/QuickJS/include/TVScript.h', '.github/workflows/build-ios.yml',
             'Config/iOS/Assets.xcassets/AppIcon.appiconset/AppIcon.png']:
    assert (root / name).is_file(), name
# XcodeGen includes the App directory as it exists on the runner. Missing uploads
# otherwise surface much later as "cannot find ... in scope" during compilation.
for name in ['AppAppearance.swift', 'BookDetailView.swift', 'DiscoverPageModel.swift',
             'DiscoverView.swift', 'DocumentImportPicker.swift', 'FontSettingsView.swift',
             'ReaderApp.swift', 'ReaderBackgrounds.swift', 'ReaderLibrary.swift',
             'ReaderPageSurface.swift', 'ReaderPreparedChapter.swift', 'ReaderSettingsPanel.swift',
             'ReaderView.swift', 'SearchView.swift', 'ShelfView.swift',
             'SourceBrowserView.swift', 'SourceSignInView.swift', 'SourcesView.swift']:
    assert (root / 'App' / name).is_file(), (
        f'Missing App/{name}. Upload the complete App directory from the source archive, then start a new workflow.'
    )
assets = root / 'Sources/TVCore/ScriptAssets'
for file in assets.rglob('*.js'):
    for relative in re.findall(r'''['"]assets://([^'"\s]+\.js)['"]''', file.read_text(encoding='utf-8')):
        assert (assets / relative).is_file(), (file, relative)
for file in root.rglob('*.json'):
    if 'build' not in file.parts:
        json.loads(file.read_text(encoding='utf-8'))
for file in (root / 'Sources/TVCore').glob('*.swift'):
    assert not file.name.startswith(('Music', 'Manga', 'Cloud', 'Live', 'Playback', 'Subtitle', 'Embedded'))
project = (root / 'project.yml').read_text(encoding='utf-8')
assert 'platform: iOS' in project and 'UIBackgroundModes' not in project
assert 'ReaderCoreTests' in project
print('PASS: project files, bundled JS dependencies, JSON, reader-only source inventory')
