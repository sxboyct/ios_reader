# 映匣阅读 · iOS

从 [jo32/tvbox-silicon](https://github.com/jo32/tvbox-silicon) 提取的独立文字阅读应用，支持 iOS 17+ 的 iPhone / iPad。

保留上游 Legado JavaScript 规则引擎、Swift 书源模型、搜索聚合、章节缓存、书架与书签模型、简繁转换。当前版本 1.2.0，主界面只有「书架 / 找书 / 书源」，字体管理在阅读设置中。没有影视、直播、音乐、有声书播放、漫画、网盘、广告、远程错误上报，以及 Java / Python / Node 应用运行时。

## 阅读

1. 在「书源」粘贴文字书源地址，或导入 JSON / XBS。支持 Legado 对象/数组以及香色的别名包装对象，文件最大 32 MB；非文字源会过滤。
2. 启用所需书源，在「找书」搜索书名或作者，再选择具体书源。
3. 打开章节后进入独立全屏阅读，默认隐藏主导航、顶部标题栏、状态栏、进度和底部横条。点击页面中间显示菜单，左上角退出。菜单里的「设置」可调整状态栏、横条、进度显示、字号、行距、主题、简繁和字体。
4. 默认左右平移翻页；点击左右侧或滑动都可以翻页。在「设置 → 翻页方式」可选择平移、仿真（系统卷页）、覆盖、渐隐、上下、滚动，开关动画并调整点击区域。系统「减弱动态效果」开启时停用动画。章末继续翻页进入下一章，章首先向前翻进入上一章末页；滚动模式可上下拉越过章界，也可通过菜单切章。
5. 分页按屏幕尺寸、实际字体、字号和行距计算，长段落可跨多页。页码滑块位于阅读菜单。保存章节和文字位置，换字号/横竖屏后重新分页；旧版段落进度与书签继续可读。预读后续章节，已缓存的章节可离线阅读；系统可能清理缓存，这不是永久离线下载功能。

## iPhone 本地文件导入

1. 「书源 → 从 JSON / XBS 文件导入 → 选择 JSON / XBS 文件」，使用系统文档选择器复制导入，文件不需要提供编辑权限。
2. 如果 `suduguu.json` 仍显示灰色，返回导入页，选「从文件夹导入」，进入其所在文件夹，点系统的「打开」。随后在应用自己的文件列表中点击 `suduguu.json`。该列表直接按文件名列出 JSON/XBS，不依赖文件提供器的类型标签；可进入子文件夹。
3. 也可在「文件」App 长按 JSON/XBS → 分享 → 映匣阅读，触发导入。请先让 iCloud/第三方提供器完成下载。

1.1.0 仅放宽 SwiftUI fileImporter 的类型并未解决用户在 iPhone 17 / iOS 26.6.1 上的置灰问题。1.2.0 已替换为 UIKit 文档选择器（复制模式），并提供文件夹授权路径和系统打开文件入口。这些原生交互还需在该设备版本上验收，不以静态检查替代真机结果。

## 香色书源兼容范围

可直接导入附件形状的 `{"alias":{"sourceName":...,"sourceUrl":...,"searchBook":...}}` JSON，也可解码该 JSON 的标准 XXTEA XBS 容器。规则保留原文，通过独立香色引擎执行；内部书源标识与 Legado 隔离。

当前支持 DOM / html、XPath（含列表子项、属性和联合选择）、`@js:` 请求及字段处理、`%@result`、`config.host` / `params.keyWord` / `queryInfo`、POST/httpParams/httpHeaders、UTF-8/GBK 响应、正文与目录 `nextPageUrl` 分页、循环与跨章保护。复杂 JS parser、JSONPath、nativeTool、香色 WebView/嗅探、响应解密、非空 validConfig、GBK POST 参数编码尚不支持，会显示错误；不声称完整复刻 StandarReader。

附件 `suduguu.source.json` 未修改，作为开发测试样本保存在 `Tests/Fixtures/`，不自动安装进 App。2026-11-23 对原始规则的独立联网验证取得 10 条搜索结果、999 条目录以及首章 4 页正文。网站实际还有下一页目录，但附件 `chapterList` 没有 `nextPageUrl`，因此仅返回第一页目录；简介 XPath 也未匹配当前页面。以上属于附件规则限制，详见 `Docs/xiangse-live.json`，不代表 iOS 或香色官方 App 已验收。

## 导入和切换字体

阅读时点击屏幕中间 →「设置」→「导入与更换字体」→「导入 TTF / OTF 字体」。导入后立即使用该字体，支持预览、系统字体切换、左滑删除；字体复制到应用内部并在重启时重新注册。每个文件最大 32 MB，文件内容和内部字体名均会验证，重复文件不会重复添加。

附件「笔落纸端勾勒回忆.ttf」已用 FontTools 检查，内部 PostScript 名为 `BiLZDGLHYSS`，包含 10575 个映射字符。App 的字体列表使用字体内部名称，不一定等于文件名。用户字体没有内置到源码或安装包；请在 App 中导入原文件。CoreText 真机显示效果仍需 iOS 验证。

这个移植对应上游的在线小说功能，不是 EPUB/PDF 阅读器。不附带第三方书源或书籍。当前界面不包含背景图片、探索分类和书源登录表单；需要交互登录的书源暂不适用。已保留通用规则引擎及 WebKit 页面解析能力，网站规则失效、验证码或网络错误仍可能导致读取失败。

## GitHub Actions 打包

将**本目录内的文件**作为 GitHub 仓库根目录上传，注意包含 `.github` 隐藏目录。无需上传外层工作区或原仓库。

1. 打开 GitHub 仓库 → Actions → **Build iOS Reader** → Run workflow。
2. 工作流在 macOS 上安装 XcodeGen、生成 Xcode 项目、执行 iOS 模拟器测试、构建 Release 真机应用并封装 IPA。
3. 成功后在该次运行的 Artifacts 下载 **YingxiaReader-iOS-unsigned**，解压得到 `YingxiaReader-unsigned.ipa`。

默认不需要证书 Secrets，产物**未签名**。IPA 需要使用你自己的 Apple 账号和签名工具重签后安装，无法直接点击安装，也不能直接上传 App Store/TestFlight。此工作流不会自动发布 Release。

## 在 Mac 上构建 / 签名

安装 Xcode（支持 Swift 6 / iOS 17+ SDK）及 XcodeGen 后运行：

```sh
brew install xcodegen
python3 scripts/check-project.py
xcodegen generate
open YingxiaReader.xcodeproj
```

选择 `YingxiaReader` scheme。若通过 Xcode 安装真机，在 `project.yml` 将 `CODE_SIGNING_ALLOWED` 改为 `YES`，使用自己的唯一 Bundle ID，重新生成项目，并在 Signing & Capabilities 中选择自己的 Team / 自动签名。不要提交证书或密码。

## 验证与来源

```sh
python3 scripts/check-project.py
node --experimental-vm-modules scripts/test-engine.mjs
node --experimental-vm-modules scripts/test-xiangse.mjs
```

Node 仅用于开发时验证规则引擎，不打包进 App。Swift 原生测试由 Actions 执行，包括实际 QuickJS 引擎启动和规则提取测试、书签与简繁转换测试。

本次工作在 Windows 完成；结构检查及 JavaScript 规则链验证不能替代 Xcode 编译、模拟器运行或真机验收。尚未运行远程 Actions，也尚未产出经验证的 IPA。

`UPSTREAM.json` 记录本地原仓库快照的 SHA-256；书源功能取自该快照，共享脚本桥接辅助代码取自工作区已有的同仓库精简衍生版。完整项目遵循 GPL-3.0-only，详见 `LICENSE` 与 `Docs/THIRD_PARTY_NOTICES.md`。
