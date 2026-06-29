# Altp

Altp 是一个 macOS 窗口切换器原型：用 `Option + Space` 唤起类似 Spotlight 的搜索框，输入 App 名称或窗口标题后按回车切换到对应窗口。

## 功能

- 枚举当前运行 App 的窗口，而不是只切换 App。
- 搜索窗口标题、App 名称和 bundle identifier。
- 方向键选择，回车切换，Esc 关闭。
- 支持最小化窗口恢复后切换。
- 菜单栏常驻，默认不占用 Dock。
- Preferences 窗口支持配置快捷键、开机启动和查看辅助权限状态。

Altp 是菜单栏 App，打开后不会出现在 Dock。启动成功后可以在菜单栏看到 `Altp`，也可以按 `Option + Space` 唤起搜索框。菜单栏里的 `Preferences...` 可以配置快捷键、开机启动和辅助权限。重复双击 `Altp.app` 会重新弹出搜索框。

如果要开启 `Launch at Login`，先把 `Altp.app` 移到 `/Applications` 后再打开；从 `Downloads` 或开发目录直接运行时，macOS 可能不会允许注册登录项。

## 构建

```bash
./scripts/build_app.sh
```

构建完成后会生成：

```text
dist/Altp.app
```

运行：

```bash
open dist/Altp.app
```

默认 Bundle ID 是：

```text
com.miracleagi.altp
```

App 图标文件在：

```text
assets/AppIcon.icns
```

如果需要重新生成图标：

```bash
swift scripts/generate_icon.swift
```

本地开发构建会优先使用 `Apple Development` 证书签名；如果没有可用证书，脚本会失败，避免退回 ad-hoc 签名导致辅助功能权限在每次 rebuild 后失效。临时测试可以显式允许 ad-hoc：

```bash
ALTP_ALLOW_ADHOC=1 ./scripts/build_app.sh
```

## 发布

正式发给其他人使用时，需要使用 `Developer ID Application` 证书签名、启用 Hardened Runtime，并提交 Apple notarization。先确认本机有 Developer ID 证书：

```bash
security find-identity -v -p codesigning
```

第一次发布前，把 notarization 凭据存到 Keychain：

```bash
xcrun notarytool store-credentials altp-notary \
  --apple-id <apple-id> \
  --team-id 35NCMHD8DT \
  --password <app-specific-password>
```

`<app-specific-password>` 需要在 Apple ID 账号里创建，不是 Apple ID 登录密码。

生成发布包：

```bash
ALTP_NOTARY_KEYCHAIN_PROFILE=altp-notary ./scripts/release.sh
```

如果本机有多个 Developer ID 证书，可以显式指定：

```bash
ALTP_DEVELOPER_ID_IDENTITY="Developer ID Application: Zheng Chuanchuan (35NCMHD8DT)" \
ALTP_NOTARY_KEYCHAIN_PROFILE=altp-notary \
./scripts/release.sh
```

发布脚本会执行：

```text
build -> Developer ID signing with Hardened Runtime -> zip -> notarization -> staple -> final zip
```

最终产物：

```text
dist/release/Altp-0.1.1-macOS.zip
```

发布前可以验证 Gatekeeper 是否接受：

```bash
spctl -a -vvv -t exec dist/Altp.app
```

## 权限

macOS 要求授予辅助功能权限后，App 才能读取和聚焦其他 App 的窗口。首次运行会弹出授权提示；也可以手动打开：

System Settings -> Privacy & Security -> Accessibility

把 `Altp.app` 加进去并打开开关后，回到 Altp 点 `Retry` 或重新打开搜索框。

## 快捷键

默认快捷键是 `Option + Space`，避免和系统 Spotlight 的 `Command + Space` 冲突。如果你已经关闭 Spotlight 快捷键，可以在 `Sources/Altp/AppDelegate.swift` 里把 `UInt32(optionKey)` 改成 `UInt32(cmdKey)`。
