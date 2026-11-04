# Pitchee iOS

基于 [Pitchee Android](https://github.com/Project-Pitchee/Pitchee-Android) 的原生 iOS 移植。界面使用 **SwiftUI / Swift**，录音使用 AVAudioEngine，分析复用 PitcheeCore C++、原始 ncnn 模型与评分规则。最低 iOS 16，支持 iPhone / iPad。许可证 GPL-3.0-only。

## 已实现

- 5–120 秒本地录音，女性化 / 男性化评分、音色、自然度、平均音高。
- 单独声音健康分析。
- 历史记录、按日期筛选、分训练方向的趋势图、录音回放、JSON 分享、删除。
- 实时音高和频谱、C3–C6 合成钢琴、内置中文知识库。
- 训练方向与音频保留设置，麦克风权限与后台录音停止处理。

实时音高使用自相关估计，正式录音分析使用原版 SwiftF0。知识库目前按原始 Markdown 文本显示（包含公式源码）。钢琴是合成音色。暂未迁移 Android 的 PDF 报告、主题系统、英文界面和全部训练建议，不能视为 Android 全功能等价版本。

## 没有 Mac：用 GitHub Actions 构建

1. 在自己的 GitHub 账号创建仓库，将本目录的源码上传。`upstream/`、`android.zip`、`build/` 不上传。
2. 默认分支使用 `main`；推送后，或进入 **Actions → iOS Release → Run workflow** 即可运行。
3. 工作流先在 macOS 模拟器执行 Swift 测试和真实语音模型推理测试，再编译 arm64 Release 真机包。
4. 成功后在该次运行的 **Artifacts → Pitchee-iOS-运行编号** 下载 IPA。
5. 推送 `ios-v1.0.0` 等 tag 会自动建立 GitHub Release，附上未签名 IPA。已有同名 Release 会让发布步骤失败，应使用新版本 tag。

默认无需任何 Secrets，会产出 `Pitchee-unsigned.ipa`。**Release 优化构建不等于已签名发行包：未签名 IPA 不能直接在普通 iPhone 上安装，需有效签名。** GitHub Release 也不等于 App Store / TestFlight 发布。

本地 Windows 可编辑代码。Xcode 项目由 `project.yml` 自动生成；不需要在 Windows 安装 Xcode。已在 GitHub macOS runner 通过 Swift 编译、真实语音模型推理测试及真机 arm64 Release 归档，生成未签名 IPA：[成功构建](https://github.com/LanternYoru/Pitchee--iOS/actions/runs/41813140637)。签名安装、真机录音与蓝牙路由仍需设备验证。

## Apple 签名发行

在 Apple Developer 网站创建与 Bundle ID 对应的 App ID，取得证书、证书的私钥和匹配的 provisioning profile。若有 `.cer` 但没有配套私钥，无法用它签名。证书申请时需保留生成 CSR 的私钥，可在 Windows 使用 OpenSSL 生成 CSR 并将证书和私钥导出为 `.p12`，不必在本机拥有 Mac。

仓库 **Settings → Secrets and variables → Actions** 配置：

| 类型 | 名称 | 内容 |
| --- | --- | --- |
| Variable | `IOS_BUNDLE_ID` | 例如 `space.yourname.pitchee`，默认 `space.pitchee.ios` |
| Secret | `IOS_TEAM_ID` | Apple Team ID |
| Secret | `IOS_CERTIFICATE_P12_BASE64` | 包含私钥的 P12 文件 Base64 |
| Secret | `IOS_CERTIFICATE_PASSWORD` | P12 密码（设置非空密码） |
| Secret | `IOS_PROVISION_PROFILE_BASE64` | provisioning profile 文件 Base64 |

Windows PowerShell 编码文件示例：

```powershell
[Convert]::ToBase64String([IO.File]::ReadAllBytes('C:\certificates\distribution.p12')) | Set-Clipboard
```

手动 Run workflow 勾选 `signed`，选择与 profile 相符的 `ad-hoc`、`app-store` 或 `development`。签名资产只在手动签名构建中导入；工作流会验证 Team ID / App ID、创建临时 keychain，并在结束时清理。证书和 profile 不要提交进 Git。

- Ad Hoc 需要 profile 包含安装设备的 UDID。
- App Store 方式导出的 IPA 用于 App Store Connect，不能作为普通侧载包直接安装。
- 本流程导出并上传 Actions artifact，不自动上传 App Store Connect / TestFlight。上架前仍需图标、商店资料、隐私披露及 Apple 审核。
- 标签触发的 GitHub Release 固定发布未签名包；手动签名包从对应 Actions artifact 下载。

## 工程结构与测试

`Sources/` 为 SwiftUI、录音、存储与工具；`Vendor/PitcheeCore/` 为上游内核和模型；`Scripts/` 为构建签名脚本；`.github/workflows/ios.yml` 为云端测试、打包与标签发行。

在 Mac / GitHub macOS runner：

```bash
brew install cmake ninja xcodegen
bash Scripts/build.sh iphoneos
xcodebuild -project Pitchee.xcodeproj -scheme Pitchee -configuration Release \
  -destination 'generic/platform=iOS' -archivePath build/Pitchee.xcarchive \
  CODE_SIGNING_ALLOWED=NO archive
```

模拟器使用 `bash Scripts/build.sh iphonesimulator`，再运行 `xcodebuild test`。模拟器和真机构建请分别使用独立工作目录，公共 `build/native/lib` 一次只保存一种 SDK 的库。

测试包含真实语音经过全部模型的分析、结果 JSON 解码与评分范围检查，以及实时估计对正弦波与静音的检测。真机的麦克风权限、蓝牙路由、音频中断、性能和签名安装仍需设备测试。

## 来源与改动

上游快照：`Project-Pitchee/Pitchee-Android@1f5d95f4932bc619d36f598c192b9c5e68023c50`。

保留 GPL 原文及模型许可。新增 Swift iOS 应用和构建流程；在 `Vendor/PitcheeCore/src/model_runtime.cpp` 中为 Apple 平台默认选择 ncnn；通过根目录 CMake 构建静态 Core 与 ncnn，避免原 Android CMake 的 Android 系统库与 OpenMP 依赖。ncnn 固定到 `c4193aadbbb56582aa87b1850dd3d98fb8fd936d`（20250916），运行时仅 CPU 推理，不启用 Vulkan / ONNX Runtime。

上游模型的统计性质和适用范围不因移植改变；评分用于观察变化。原始项目对算法及训练数据的说明见上游 README。

