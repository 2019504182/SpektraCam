# SpektraCam 原项目检查与工作流交付记录

核查日期：2026-11-03。目标按用户最新说明确定为 **iPhone 15 / iOS 27.2**，不再处理 iOS 27.0.1。

## 检查基线

- 仓库：[runzeni/SpektraCam](https://github.com/runzeni/SpektraCam)。
- 分支：`main`。
- 实际检查提交：[c0984d4e37d60cca2ec5e658d2bf35bc0d4f0758](https://github.com/runzeni/SpektraCam/tree/c0984d4e37d60cca2ec5e658d2bf35bc0d4f0758)。
- App 版本：`0.2.3`，build `8`。
- 原项目 80 个 App Swift 源文件；另有 UI 测试和用于原生数值验证的脚本。
- 未发现 `AGENTS.md`、原有 Actions YAML、第三方包管理清单或 `.entitlements` 文件。

已创建用户的 [2019504182/SpektraCam](https://github.com/2019504182/SpektraCam) fork，并在 main 提交工作流：[28bc6ec4c34d380c799613d625cec73efb2e7f39](https://github.com/2019504182/SpektraCam/commit/28bc6ec4c34d380c799613d625cec73efb2e7f39)。该提交只添加工作流，业务源码仍为上述 upstream 基线。以后手动运行将构建 fork 所选分支的实际提交，不会从 upstream main 偷换源码。

## 工程与依赖

| 项目 | 原始状态与实施判断 |
| --- | --- |
| 工程 | `SpektraCam.xcodeproj/project.xcproj`，JSON 风格并带尾随逗号；不是旧式 `project.pbxproj`。保留原格式，使用 Xcode 27.2 读取。 |
| 共享 Scheme | `SpektraCam`。App 可 Archive，UI 测试 target 的 `buildForArchiving` 为 `NO`。 |
| 最低系统 | 工程级 `IPHONEOS_DEPLOYMENT_TARGET = 27.2`；保留。 |
| 设备 | `TARGETED_DEVICE_FAMILY = 1`，iPhone，界面竖屏；工作流编译 `arm64` 真机。 |
| Swift | `SWIFT_VERSION = 5.0` 表示语言模式，编译器来自实际选中的 Xcode 27.2；工程启用 approachable concurrency 与默认 MainActor 隔离。 |
| 签名 | 原工程为自动签名，带作者 Team ID。CI 命令覆盖为空并禁用签名，不写入作者账号材料，不修改工程文件。 |
| Info.plist | 由 Xcode 生成；工程提供相机、定位、照片新增用途说明。未通过改 Info.plist 降低版本限制。 |
| 构建阶段 | App 和测试均为 sources / frameworks / resources，未发现自定义 shell script build phase。 |
| 第三方依赖 | 无 CocoaPods、SPM、Carthage 依赖声明或锁文件；无需 `pod install`。 |
| 原有构建脚本 | `Scripts/build-and-run.py` 固定 `/Applications/Xcode.app`，构建 Debug / iphonesimulator；不适合产出 iPhone 安装包，本次没有调用或改动它。 |
| 原有测试脚本 | `Scripts/core-checks.py` 调用 Swift 编译器做 macOS／模拟器数值检查，`--simulator` 还要求已启动的模拟器；UI 测试需要预放两张照片。本次不把这些结果冒充真机安装验证。 |
| Python 参考环境 | `Reference/requirements.lock` 包含 numpy、scipy、rawpy 等，用于参考模型及 fixtures，不是 App 编译依赖。CI 内嵌校验只用 Python 标准库。 |
| 模型资源 | `SpektraCam/Resources/ModelData` 有光谱表、StockProfiles、许可与 5 份 `.metalSource`。源码 `PhotoLibrary` 从 `Bundle.main.resourceURL` 读取，因此 CI 要求这些文件在 bundle 根部存在。 |

App 导入的系统模块包括 SwiftUI、UIKit、SwiftData、Observation、Photos/PhotosUI、AVFoundation、CoreLocation、MapKit、CoreImage、ImageIO、Metal、MetalPerformanceShaders、MetalPerformanceShadersGraph、Accelerate、CryptoKit 等；没有发现外部二进制 SDK 的引入。

工程格式参考：[Apple：Updating your Xcode project configuration file format](https://developer.apple.com/documentation/xcode/updating-your-xcode-project-configuration-file-format)。原工程和共享 Scheme 可在上述基线提交中复查。

## 系统 API 核查

检查了相机的设备枚举与 RAW 能力判断、地图反向地理编码、SwiftUI 玻璃与工具栏、CoreImage RAW 解码、SwiftData、本地数据与 Metal/MPSGraph 渲染路径。以下是针对源码实际出现的 12 个关键符号，从 Apple 文档 JSON 的 `metadata.platforms` 读取到的 iOS 引入版本；原始摘录随包保存为 `docs/api-availability.json`。

| 实际符号 | iOS 引入版本 | 源码位置 |
| --- | --- | --- |
| [AVCaptureDevice.nominalFocalLengthIn35mmFilm](https://developer.apple.com/documentation/avfoundation/avcapturedevice/nominalfocallengthin35mmfilm) | 26.0 | `Features/Camera/CameraService.swift` |
| [AVCaptureVideoDataOutput.deliversPreviewSizedOutputBuffers](https://developer.apple.com/documentation/avfoundation/avcapturevideodataoutput/deliverspreviewsizedoutputbuffers) | 13.0 | `Features/Camera/CameraService.swift` |
| [AVCaptureDevice.RotationCoordinator](https://developer.apple.com/documentation/avfoundation/avcapturedevice/rotationcoordinator) | 17.0 | `Features/Camera/CameraPreview.swift` |
| [AVCapturePhotoOutput.captureReadiness](https://developer.apple.com/documentation/avfoundation/avcapturephotooutput/capturereadiness-swift.property) | 17.0 | `Features/Camera/CameraService.swift` |
| [MKReverseGeocodingRequest](https://developer.apple.com/documentation/mapkit/mkreversegeocodingrequest) | 26.0 | `Features/Viewer/PhotoDetailView.swift` |
| [MKMapItem.addressRepresentations](https://developer.apple.com/documentation/mapkit/mkmapitem/addressrepresentations) | 26.0 | `Features/Viewer/PhotoDetailView.swift` |
| [GlassEffectContainer](https://developer.apple.com/documentation/swiftui/glasseffectcontainer) | 26.0 | 相机、编辑、导出等视图 |
| [ToolbarSpacer](https://developer.apple.com/documentation/swiftui/toolbarspacer) | 26.0 | `Features/Editor/EditorToolbar.swift` |
| [MTLCompileOptions.mathMode](https://developer.apple.com/documentation/metal/mtlcompileoptions/mathmode) | 18.0 | `Rendering/Metal/*.swift` |
| [MPSGraphFFTDescriptor](https://developer.apple.com/documentation/metalperformanceshadersgraph/mpsgraphfftdescriptor) | 17.0 | `Rendering/Metal/MetalDiffusion.swift` |
| [CIRAWFilter](https://developer.apple.com/documentation/coreimage/cirawfilter) | 15.0 | `Rendering/SourceImageRenderer.swift` |
| [ModelContainer](https://developer.apple.com/documentation/swiftdata/modelcontainer) | 17.0 | `Features/Library/PhotoLibrary.swift` |

这些符号的声明可用版本均不高于目标 27.2，没有因此改写功能或增加替代 UI。完整源码仍须由云端 Xcode 做实际类型检查与链接；没有关闭 Swift availability 检查。这个核查表不是“每个系统符号和每个硬件路径都已运行验证”的承诺。

相机代码查询 `isAppleProRAWSupported`、枚举 `availableRawPhotoPixelFormatTypes`，没有 RAW 格式时会抛出 `rawUnavailable`。这属于设备能力判断，不能用系统版本或签名解决。普通 iPhone 15 的拍摄路径须单独实测，不能等同于 Pro 机型。

渲染器用 `device.makeLibrary(source:options:)` 在真机运行时编译资源中的 Metal 源码；真机 MPSGraph FFT 路径与 `#if targetEnvironment(simulator)` 中的替代路径也不同。因此 Archive 成功不会证明 GPU 特效已经实际运行成功。

## Xcode 运行器选择

[GitHub 官方公告](https://github.blog/changelog/2026-10-15-xcode-27-runner-image-generally-available/)给出的标准标签为 `xcode-27`，为 Apple Silicon 托管运行器。

2026-11-03 查阅的[镜像软件清单](https://github.com/actions/runner-images/blob/main/images/macos/xcode-27-arm64-Readme.md)显示：

- 镜像 `20261026.0314.1`，系统 macOS 27.0.1。
- 默认 Xcode 为 27.1。
- Xcode 27.2 为 build `27B48`，实际路径 `/Applications/Xcode_27.2_Release_Candidate.app`。
- `/Applications/Xcode_27.2.app` 为其别名；包含 iOS 27.2 SDK。

工作流通过 `DEVELOPER_DIR` 显式选择该 27.2 别名，并在运行时检查版本和 SDK、记录完整 build number。当前清单提供的是 27.2 RC，不能称为已确认安装了 27.2 正式版。以后别名若更新到正式版，也会在日志中反映。若别名或所需版本缺失，工作流会明确失败，不静默降级。

## 工作流行为

唯一必需文件：`.github/workflows/unsigned-ipa.yml`。

1. 仅接受 `workflow_dispatch` 手动触发，`contents: read`。
2. 检出当前 fork 的所选提交，不持久化 GitHub 凭据。
3. 检查工具链、读取工程和有效 build settings。
4. Release / iphoneos / generic iOS / arm64 执行 `xcodebuild archive`。禁用代码签名、清空 Team 和签名身份，不请求 provisioning updates。
5. 从 `.xcarchive/Products/Applications` 复制 App；清除可能出现的临时 ad-hoc 签名及描述文件。
6. 检查 Info.plist、Mach-O 平台和 minOS、arm64、未加密状态、主程序未签名、14 份模型文件 SHA-256、隐私 manifest 和编译后的 assets。
7. 把 `Payload/SpektraCam.app` 打包为 IPA，输出 SHA-256 与来源信息。不走要求签名导出的 `-exportArchive`。
8. 成功才上传 IPA Artifact；无论失败与否都尝试上传已生成日志。所有编译管道都启用 `pipefail`，不会用 `tee` 吞掉 xcodebuild 失败。

构建结果不会上传 App Store、TestFlight 或 GitHub Release。安装时由 Windows 上的 Sideloadly 签名。

## 已完成的验证与未完成的验证

| 验证 | 实际结果 |
| --- | --- |
| YAML 解析与 8 个步骤检查 | 通过 |
| 两段内嵌 Python 语法解析 | 通过 |
| actionlint 1.7.12 | 通过；命令禁用外部 shellcheck 和 pyflakes，未将它们声称为已运行。 |
| 运行器标签核对 | `xcode-27` 已与 GitHub 官方公告核对。actionlint 内置列表尚无此标签，校验时用单独配置允许这个精确标签；实际 workflow 仍为 GitHub 托管运行器。 |
| 模型资源 14 个 SHA-256 | 通过；用原始 Git blob 核查，避免 Windows checkout 的 CRLF 转换影响文本 hash。云端会检查打包后的实际文件。 |
| 原有受版本控制文件 | 未修改；仅新增工作流与说明文档。 |
| macOS / Xcode 编译 | **实际通过**。Actions #1 全部步骤成功，日志包含 `ARCHIVE SUCCEEDED`，总时长 1 分 18 秒。 |
| 云端 IPA 检查与上传 | **实际通过**；IPA 和完整构建日志均已上传 Artifact。 |
| Windows 下载后检查 | **实际通过**：Artifact ZIP digest、IPA SHA-256、ZIP CRC、Info.plist、Mach-O arm64 / iOS / minOS 27.2、无签名加载命令、无描述文件及 14 份模型资源 SHA-256。 |
| 真机安装与运行 | **未执行**；仍需 Sideloadly 中的本人 Apple 登录和 iPhone 操作。 |
| 依据编译日志修复 | 首次真实编译成功，未出现需要修复的编译失败，没有修改业务源码。 |

静态检查期间发现并修正了工作流中 `runner.temp` 在 job 级 env 不可用的问题：改为在首个脚本步骤用 `$RUNNER_TEMP` 写入 `$GITHUB_ENV`。这属于实际 actionlint 输出指向的配置问题，不是 Xcode 编译问题。

## 首次真实构建证据

- [运行记录 #1](https://github.com/2019504182/SpektraCam/actions/runs/41583243902)，Job `125742697051`，状态 `success`。
- [IPA Artifact](https://github.com/2019504182/SpektraCam/actions/runs/41583243902/artifacts/13206826192)，名称 `SpektraCam-unsigned-IPA-1`。
- [日志 Artifact](https://github.com/2019504182/SpektraCam/actions/runs/41583243902/artifacts/13206434775)，名称 `SpektraCam-build-logs-1`。
- 日志实际工具链：`Xcode 27.2 / Build version 27B48`；SDK `27.2`。
- IPA：`30,347,719` 字节；SHA-256 `e953967565f06fe1f8bdd0a3d4e610774332f32b6da5fd94f3545d512d574032`。
- IPA 内可执行文件：64-bit Mach-O，CPU type ARM64，`LC_BUILD_VERSION` platform iOS / minOS 27.2.0，没有 `LC_CODE_SIGNATURE`。
- `build-info.json` 明确记录 `unsigned: true`、`verified_model_files: 14`、`device_runtime_tested: false`。
- 非阻塞提示：AppIntents metadata extraction 因项目无 AppIntents 依赖而跳过；checkout/upload-artifact v4 的 Node 20 运行时由 GitHub 自动切换到 Node 24，并产生弃用警告。两项均未导致构建或上传失败。保留已验证成功的工作流，不因无关提示改动业务功能。

构建和下载验证完成；“可由 Sideloadly 重新签名的未签名 IPA”已经生成。具体手机上的安装、权限、相机与 GPU 效果仍需真机确认，不能据 Archive 成功虚构这些测试。
