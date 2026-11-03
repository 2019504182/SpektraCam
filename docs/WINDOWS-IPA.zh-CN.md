# SpektraCam：从 Windows 构建并安装到 iPhone

适用设备：Windows 电脑、iPhone 15、iOS 27.2。无需 Mac，无需付费 Apple Developer 会员。

已替你完成 Fork、提交工作流、触发真实云端编译、下载 IPA，并在 Windows 上再次核对校验值和真实可执行文件。你无需再执行第 1–3 节，直接从第 4 节的 Sideloadly 安装开始；第 1–3 节保留用于今后复现。

- 你的仓库：[2019504182/SpektraCam](https://github.com/2019504182/SpektraCam)。
- 已成功的构建：[Actions #1](https://github.com/2019504182/SpektraCam/actions/runs/41583243902)。
- 本地安装包：与本说明一起交付的 `SpektraCam-unsigned.ipa`（30,347,719 字节）。
- 实际工具链：Xcode 27.2 / 27B48（RC），iOS SDK 27.2；App 0.2.3（8），arm64，最低 iOS 27.2。
- IPA SHA-256：`e953967565f06fe1f8bdd0a3d4e610774332f32b6da5fd94f3545d512d574032`。
- 已确认 IPA 未签名、无加密、14 份模型资源完整；尚未在你的 iPhone 上安装或测试功能。

## 1. 建立自己的 GitHub 仓库

1. 注册或登录 [GitHub](https://github.com/)。只需要普通 GitHub 账号。
2. 打开 [runzeni/SpektraCam](https://github.com/runzeni/SpektraCam)。
3. 点击右上角 **Fork**，Owner 选择你自己的账号，仓库名称保留 **SpektraCam**，点击 **Create fork**。新仓库网址应是 `https://github.com/你的用户名/SpektraCam`。
4. 在你自己的仓库打开 **Actions**。若出现提示，点击 **I understand my workflows, go ahead and enable them**，或相应的启用按钮。

GitHub 官方的普通 `xcode-27` 托管运行器可用于这个任务。不需要选择 `xcode-27-xlarge`。公共仓库使用标准托管运行器通常免费，账号仍须符合 GitHub 的使用条件；若提示额度、账号验证或组织策略限制，按 GitHub 页面处理。

## 2. 添加一个工作流文件

无需 Git、终端、Python 或本机 Xcode。采用网页编辑最容易避免把文件放错位置。

1. 下载配置包并解压。找到 `.github/workflows/unsigned-ipa.yml`。也可以直接下载单独提供的 `unsigned-ipa.yml`。
2. 用 Windows 记事本打开这个 YAML，按 **Ctrl+A → Ctrl+C** 复制全文。
3. 打开你 fork 的仓库，进入 **Code**，确认当前分支是 **main**。
4. 点击 **Add file → Create new file**。
5. 文件名填完整路径：

   ```text
   .github/workflows/unsigned-ipa.yml
   ```

6. 把 YAML 全文粘贴到编辑区。文件必须以 `name: Build unsigned iPhone IPA` 开头，不要复制 Markdown 的三个反引号。
7. 点击 **Commit changes**，提交说明可填 `Add unsigned iPhone IPA build`。选择直接提交到 **main**，确认提交。

只需添加这一个 YAML。文档和 API 核查记录供你参考，不是构建依赖。不要把整个配置 ZIP 上传为仓库中的单个文件，也不要把 YAML 放在仓库根目录。

## 3. 手动编译和下载 IPA

1. 打开自己仓库的 **Actions**。
2. 左侧选择 **Build unsigned iPhone IPA**。
3. 点击 **Run workflow**，Branch 选择 **main**，再点击绿色 **Run workflow**。
4. 打开新出现的运行记录。排队和编译需要一些时间，页面会显示各步骤状态。
5. 全部成功后，在运行记录的 **Summary → Artifacts** 下载：

   ```text
   SpektraCam-unsigned-IPA-数字
   ```

6. 下载的是 GitHub 生成的 **ZIP**。用 Windows“全部解压”，其中应有：

   ```text
   SpektraCam-unsigned.ipa
   build-info.json
   SHA256SUMS.txt
   ```

7. 后面交给 Sideloadly 的文件是 **SpektraCam-unsigned.ipa**。不要把外层 Artifact ZIP 改名为 IPA，也不要继续解压 IPA。

产物和日志保存 14 天，到期后可以重新手动构建。`build-info.json` 记录实际源码提交、Xcode 版本及 build number、SDK、App 版本和检查结果。它也明确标记真机运行测试尚未完成。

可选：在解压目录打开 PowerShell，执行下列命令，将显示的 Hash 与 `SHA256SUMS.txt` 比较：

```powershell
Get-FileHash .\SpektraCam-unsigned.ipa -Algorithm SHA256
```

## 4. 在 Windows 准备 Sideloadly

1. 打开 [Sideloadly 官方网站](https://sideloadly.io/)，下载 Windows 版本。通常使用 64 位版。
2. 按官网“Before you install”的要求，安装其链接提供的 **网页版 iTunes 和 iCloud**。如果已有 Microsoft Store 版，按官网指示卸载后改用网页版。链接与驱动要求可能更新，以官网为准。
3. 安装完成后重启 Windows。
4. 用支持数据传输的 USB-C 线连接 iPhone 15，解锁手机，在手机提示中点击 **信任此电脑**，输入手机解锁密码。
5. 打开 iTunes，确认可以看到这台 iPhone。然后打开 Sideloadly，在设备列表中选中它。

## 5. 签名并安装

1. 将解压得到的 **SpektraCam-unsigned.ipa** 拖入 Sideloadly。
2. 保持默认的 Apple ID 侧载安装模式，不要选仅导出或仅普通安装。
3. 在 Sideloadly 的 Apple ID 栏填写你自己的 Apple 账号。免费账号即可。此阶段的 Apple 登录、手机信任与开发者模式需要你本人完成。
4. 点击 **Start**。如 Sideloadly 弹出登录窗口，在你自己的电脑上完成密码和双重认证。**不要把密码、验证码、证书或描述文件发到本聊天，也不要放到 GitHub、workflow、Actions Secrets 或仓库里。**
5. 保持手机连接并解锁，等待 Sideloadly 显示安装完成。
6. 若手机提示“不受信任的开发者”，进入 **设置 → 通用 → VPN 与设备管理**，选择相应 Apple 账号的开发者项目并信任。按系统提示完成操作。
7. 如提示需要开发者模式，进入 **设置 → 隐私与安全性 → 开发者模式**，打开，重启手机，并在重启后按提示确认。如果起初看不到该选项，先执行一次侧载并检查系统提示，再查看设置。
8. 打开 SpektraCam，使用相机、保存照片或定位时按需要授予权限。

不需要在 GitHub 上配置任何 Apple 账号或签名材料。云端生成的 IPA 没有可直接运行的 Apple 签名；Sideloadly 在安装阶段使用你的账号完成签名和配置。

保留默认设置开始安装。不要使用 Sideloadly 的“修改最低 iOS 版本”功能，你的 iOS 27.2 已符合工程要求。若遇到 bundle ID 冲突，可在 Sideloadly 的 Advanced Options 使用一个自己固定的唯一 Bundle ID，例如 `com.你的英文用户名.spektracam`。以后更新和续签时沿用同一个账号及同一个 Bundle ID。

## 6. 免费账号的续签

- 免费账号签名通常有效 **7 天**，同时通常最多安装 **3 个**使用免费开发者描述文件的侧载 App；还有每 7 天最多创建 10 个 App ID 的限制。
- 到期前可连接手机，用同一个 Apple 账号和 Bundle ID 再次侧载同一个 IPA。无需每周重新编译。
- 可以启用 Sideloadly 自动刷新。电脑需要在适当时候开机运行 Sideloadly Daemon，手机通过 USB 或已配对的同一 Wi-Fi 网络可被访问；它不是在手机上独立完成刷新。
- Wi-Fi 刷新先通过 USB 建立连接，在 iTunes 的设备摘要里启用 **通过 Wi-Fi 与此 iPhone 同步** 并应用。首次安装建议始终使用 USB。
- 更新时尽量覆盖安装，不要先删除 App；删除可能同时删除本地照片库和编辑数据。重要照片先导出保存。

以上来自 [Sideloadly 官方 FAQ](https://sideloadly.io/faq.html)。实际限制和菜单以当时 Apple 和 Sideloadly 的提示为准。

## 7. 失败时如何定位

### Actions 没有显示工作流或 Run workflow 按钮

确认访问的是你自己的 fork，文件位于默认分支 `main` 的 `.github/workflows/unsigned-ipa.yml`，Actions 已启用。工作流只支持手动触发，提交文件不会自动运行。

### 一直排队，或提示找不到运行器

工作流使用 GitHub 正式公布的 `xcode-27` 标签。排队先看运行页面提示和 [GitHub Status](https://www.githubstatus.com/)。如果是组织的运行器限制或账单/额度问题，先处理页面明确指出的原因。不要随意改成 Windows 或旧版 macOS 标签。

### Verify Xcode and iPhone SDK 失败

打开此步骤和 `toolchain.log`。工作流要求 `/Applications/Xcode_27.2.app/Contents/Developer`，并检查 `xcodebuild -version` 和 iOS SDK 版本。2026-11-03 查到的 GitHub 镜像清单中，27.2 别名指向 **27.2 RC / 27B48**，默认 Xcode 是 27.1。工作流明确选择 27.2，并保存实际版本，不会静默使用 27.1。若后续镜像移除 27.2，需先核对新镜像清单再调整，不能仅改版本文字。

### Archive unsigned arm64 device app 失败

打开失败步骤，定位第一条具体 `error:` 及附近上下文。不要只看末尾 `ARCHIVE FAILED` 或 exit code 65。

在 Summary 的 Artifacts 中下载 `SpektraCam-build-logs-数字`，里面通常有：

- `toolchain.log`：运行器、Xcode、Swift 和 SDK 版本。
- `project.log`、`build-settings.log`：工程识别结果和实际构建设置。
- `archive.log`：完整编译输出。
- `archive.xcresult/`：Xcode 结果包，如本次构建产生了它。

只有根据这些日志才能判断具体是源码、工程格式、SDK、资源还是签名设置的问题。这个版本没有根据尚不存在的编译日志预改业务源码。之后可提供公开的 fork 或 Actions 运行链接继续排查；若没有链接权限，可提供 `archive.log`，先删去你不希望公开的信息。

### Verify app and package IPA for Sideloadly 失败

看 `package-verification.log` 和 `macho-load-commands.txt`。这一步检查架构、真实 Mach-O 最低版本、未签名状态、隐私声明、图标资源和模型数据完整性。检查失败不会继续上传安装用 IPA。若 upstream 后来改了资源布局或最低版本，需要依照实际改动更新检查，不能直接删掉失败的检查。

### Sideloadly 看不到手机

优先确认 iTunes 能识别手机、手机已解锁并信任电脑，改用数据线或换 USB 口。按官网 FAQ 核对网页版 iTunes/iCloud 和 Apple Mobile Device 驱动，重启后重试。

### 提示账号限制或 App ID 已用完

免费账号有 3 个已安装侧载 App 和每 7 天 10 个 App ID 的限制。减少已安装侧载 App，或等待 App ID 限额恢复。不要反复更换随机 Bundle ID 消耗额度。

### 安装完成但启动失败或拍照不可用

先检查开发者信任、开发者模式和签名有效期。仍失败时，在 Sideloadly 获取该 App 的设备日志；关注缺少动态库、系统 API、资源或内存终止的实际记录。

普通 iPhone 15 不等于 iPhone 15 Pro。原项目只支持 RAW 拍摄，并在运行时枚举 Bayer RAW／Apple ProRAW 支持。若相机报告设备不支持 RAW，不能通过改工作流或 Info.plist 赋予硬件能力；从“照片”或“文件”导入图片的编辑路径仍应单独测试。

## 8. 首次安装后的真机检查

建议用两张不重要的照片验证：从照片和文件分别导入 → 调整和裁剪 → 应用胶片或 LUT → JPEG/PNG 导出 → 退出重开并检查本地编辑是否保留。再单独检查定位和可用镜头的 RAW 拍摄。

Metal shader 使用 `.metalSource` 在运行时编译，GPU 滤镜和 MPSGraph 的实际运行结果不能仅由 `xcodebuild archive` 保证。首次先用较小图片验证，全分辨率和较强柔光可能受 iPhone 内存限制。这些是项目原有运行条件，本次没有修改。

## 参考

- [原项目与构建说明](https://github.com/runzeni/SpektraCam)
- [GitHub Xcode 27 托管运行器正式发布](https://github.blog/changelog/2026-10-15-xcode-27-runner-image-generally-available/)
- [GitHub Xcode 27 镜像软件清单](https://github.com/actions/runner-images/blob/main/images/macos/xcode-27-arm64-Readme.md)
- [Sideloadly 官网和 Windows 驱动下载入口](https://sideloadly.io/)
- [Sideloadly 官方 FAQ](https://sideloadly.io/faq.html)
