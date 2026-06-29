# Altp

Altp 是一个 macOS 窗口切换器原型：用 `Option + Space` 唤起类似 Spotlight 的搜索框，输入 App 名称或窗口标题后按回车切换到对应窗口。

## 功能

- 枚举当前运行 App 的窗口，而不是只切换 App。
- 搜索窗口标题、App 名称和 bundle identifier。
- 方向键选择，回车切换，Esc 关闭。
- 支持最小化窗口恢复后切换。
- 菜单栏常驻，默认不占用 Dock。

Altp 是菜单栏 App，打开后不会出现在 Dock。启动成功后可以在菜单栏看到 `Altp`，也可以按 `Option + Space` 唤起搜索框。重复双击 `Altp.app` 会重新弹出搜索框。

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

本地开发构建会优先使用 `Apple Development` 证书签名；如果没有可用证书，脚本会失败，避免退回 ad-hoc 签名导致辅助功能权限在每次 rebuild 后失效。临时测试可以显式允许 ad-hoc：

```bash
ALTP_ALLOW_ADHOC=1 ./scripts/build_app.sh
```

## 发布

正式发给其他人使用时，需要使用 `Developer ID Application` 证书签名并提交 Apple notarization：

```bash
xcrun notarytool store-credentials altp-notary \
  --apple-id <apple-id> \
  --team-id <team-id> \
  --password <app-specific-password>
```

生成发布包：

```bash
ALTP_NOTARY_KEYCHAIN_PROFILE=altp-notary ./scripts/release.sh
```

发布脚本会执行：

```text
build -> Developer ID signing -> zip -> notarization -> staple -> final zip
```

最终产物：

```text
dist/release/Altp-0.1.0-macOS.zip
```

## 权限

macOS 要求授予辅助功能权限后，App 才能读取和聚焦其他 App 的窗口。首次运行会弹出授权提示；也可以手动打开：

System Settings -> Privacy & Security -> Accessibility

把 `Altp.app` 加进去并打开开关后，回到 Altp 点 `Retry` 或重新打开搜索框。

## 快捷键

默认快捷键是 `Option + Space`，避免和系统 Spotlight 的 `Command + Space` 冲突。如果你已经关闭 Spotlight 快捷键，可以在 `Sources/Altp/AppDelegate.swift` 里把 `UInt32(optionKey)` 改成 `UInt32(cmdKey)`。
