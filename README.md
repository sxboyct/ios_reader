# 映匣阅读 · iOS

从 [jo32/tvbox-silicon](https://github.com/jo32/tvbox-silicon) 提取的独立文字阅读应用，支持 iOS 17+ 的 iPhone / iPad。

保留上游 Legado JavaScript 规则引擎、Swift 书源模型、搜索聚合、章节缓存、书架与书签模型、简繁转换。1.1.0 增加香色书源兼容与字体管理，界面包含「书架 / 找书 / 书源 / 字体」。没有影视、直播、音乐、有声书播放、漫画、网盘、广告、远程错误上报，以及 Java / Python / Node 应用运行时。

## 阅读

1. 在「书源」粘贴文字书源地址，或通过系统文件选择器导入 JSON / XBS。支持 Legado 对象/数组以及香色的别名包装对象，文件最大 32 MB；非文字源会过滤。选择器接受普通文件，再按扩展名及实际内容验证，避免文件提供器将 JSON 标为普通文件时无法选中。
2. 启用所需书源，在「找书」搜索书名或作者，再选择具体书源。
3. 加入书架或打开章节。滚动阅读，支持上一章 / 下一章、目录、书签、字号、行距、日夜及纸张主题、简繁转换。
4. 自动保存章节及段落位置，预读后续章节。已缓存的章节可离线阅读；系统可能清理缓存，这不是永久离线下载功能。

## 香色书源兼容范围

可直接导入附件形状的 `{"alias":{"sourceName":...,"sourceUrl":...,"searchBook":...}}` JSON，也可解码该 JSON 的标准 XXTEA XBS 容器。规则保留原文，通过独立香色引擎执行；内部书源标识与 Legado 隔离。

当前支持 DOM / html、XPath（含列表子项、属性和联合选择）、`@js:` 请求及字段处理、`%@result`、`config.host` / `params.keyWord` / `queryInfo`、POST/httpParams/httpHeaders、UTF-8/GBK 响应、正文与目录 `nextPageUrl` 分页、循环与跨章保护。复杂 JS parser、JSONPath、nativeTool、香色 WebView/嗅探、响应解密、非空 validConfig、GBK POST 参数编码尚不支持，会显示错误；不声称完整复刻 StandarReader。

附件 `suduguu.source.json` 未修改，作为开发测试样本保存在 `Tests/Fixtures/`，不自动安装进 App。2026-11-23 对原始规则的独立联网验证取得 10 条搜索结果、999 条目录以及首章 4 页正文。网站实际还有下一页目录，但附件 `chapterList` 没有 `nextPageUrl`，因此仅返回第一页目录；简介 XPath 也未匹配当前页面。以上属于附件规则限制，详见 `Docs/xiangse-live.json`，不代表 iOS 或香色官方 App 已验收。

## 导入和切换字体

打开底部「字体」→「导入 TTF / OTF 字体」，也可以从阅读页「…」→「阅读设置」→「导入与更换字体」进入。导入后立即使用该字体，支持预览、系统字体切换、左滑删除；字体复制到应用内部并在重启时重新注册。每个文件最大 32 MB，文件内容和内部字体名均会验证，重复文件不会重复添加。

附件「笔落纸端勾勒回忆.ttf」已用 FontTools 检查，内部 PostScript 名为 `BiLZDGLHYSS`，包含 10575 个映射字符。App 的字体列表使用字体内部名称，不一定等于文件名。用户字体没有内置到源码或安装包；请在 App 中导入原文件。CoreText 真机显示效果仍需 iOS 验证。

这个移植对应上游的在线小说功能，不是 EPUB/PDF 阅读器。不附带第三方书源或书籍。当前界面不包含上游的仿真翻页、背景图片、探索分类和书源登录表单；需要交互登录的书源暂不适用。已保留通用规则引擎及 WebKit 页面解析能力，网站规则失效、验证码或网络错误仍可能导致读取失败。

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
