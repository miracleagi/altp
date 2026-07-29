<p align="center">
  <img src="./assets/AppIcon.png" width="112" height="112" alt="Altp 应用图标">
</p>

<h1 align="center">Altp</h1>

<p align="center">
  <strong>一个键盘优先的 macOS 窗口切换器。</strong><br>
  按 <code>Option + Space</code> 搜索任意窗口，或按 <code>Option + Tab</code> 一次查看所有可切换窗口。
</p>

<p align="center">
  <a href="https://github.com/miracleagi/altp/releases/latest"><strong>下载最新版本</strong></a>
  ·
  <a href="./release.md">更新记录</a>
  ·
  <a href="./README.md">English</a>
  ·
  <strong>简体中文</strong>
</p>

<p align="center">
  <a href="https://github.com/miracleagi/altp/releases/latest"><img src="https://img.shields.io/github/v/release/miracleagi/altp?display_name=tag&amp;sort=semver" alt="最新版本"></a>
  <img src="https://img.shields.io/badge/macOS-13%2B-black?logo=apple&amp;logoColor=white" alt="macOS 13 或更高版本">
  <img src="https://img.shields.io/badge/Apple%20silicon-arm64-black" alt="Apple silicon arm64">
  <a href="./LICENSE"><img src="https://img.shields.io/badge/license-Apache--2.0-blue" alt="Apache 2.0 许可证"></a>
</p>

Altp 切换的是具体窗口，而不只是 App。它常驻菜单栏，提供两种互补的使用方式：知道目标时直接搜索，想浏览时用紧凑网格查看当前可用窗口。

## 主要特点

- **窗口级切换，而不是 App 级切换。** 直接进入具体的文档、浏览器窗口、终端或工作区。
- **搜索和浏览两种模式。** 使用类似 Spotlight 的搜索框，或自适应多行快速切换网格。
- **按具体窗口智能排序。** 最近使用某个窗口不会让同一 App 的所有窗口一起排到前面。
- **支持拼音搜索。** 输入 `feishu` 可以匹配名为 `飞书` 的 App 或窗口。
- **可靠激活窗口。** 可恢复最小化窗口，并切换到其他 macOS Space 中的窗口。
- **完全本地运行。** 不需要账号或网络服务；窗口信息和排序记录只保存在本机。

## 快速开始

1. 从 [最新版本](https://github.com/miracleagi/altp/releases/latest) 下载 ZIP。
2. 解压并把 `Altp.app` 移到 `/Applications`。
3. 打开 Altp。首次启动会自动显示窗口搜索面板；Altp 随后常驻菜单栏，并且不会占用 Dock。
4. 如果尚未获得辅助功能权限，请在面板的提示条中点击 `Retry`，或进入 **Settings → Permissions** 点击 `Request Permission`，然后在 macOS 系统设置中启用 Altp。

> 开启 **Launch at Login** 前，请先把 Altp 移到 `/Applications`。从其他位置运行时，Altp 会直接禁用登录项注册。

完成设置后，使用 `Option + Space` 打开窗口搜索，使用 `Option + Tab` 打开快速切换。

## 两种切换方式

| 模式 | 快捷键 | 适合场景 |
| --- | --- | --- |
| 窗口搜索 | `Option + Space` | 按 App 名、窗口标题、Bundle ID 或拼音查找窗口 |
| 快速切换 | `Option + Tab` | 在自适应网格中查看可切换窗口，并按最近使用顺序切换 |

只要当前屏幕容纳得下，快速切换会一次显示全部可切换窗口。窗口数量极多时才会启用纵向滚动，不会持续缩小卡片直到内容难以辨认。

## 键盘操作

### 窗口搜索

| 操作 | 按键 |
| --- | --- |
| 打开搜索 | `Option + Space` |
| 移动选择 | `↑` / `↓` |
| 切换到所选窗口 | `Return` |
| 关闭 | `Esc` |

### 快速切换

| 操作 | 按键 |
| --- | --- |
| 打开 / 选择下一个窗口 | 按住 `Option`，再按 `Tab` |
| 面板打开后选择上一个窗口 | 继续按住 `Option`，再按 `Shift + Tab` |
| 在网格中移动 | 方向键 |
| 切换到所选窗口 | 松开 `Option` 或按 `Return` |
| 取消 | `Esc` |

两个全局快捷键都可以在 **Settings → General** 中修改。快速切换会根据已配置的修饰键执行“松开即切换”；无修饰键快捷键会保持面板打开，直到按下 `Return` 或 `Esc`。

## 设置

点击菜单栏中的 `Altp`，选择 `Settings...`，可以配置：

- 窗口搜索和快速切换快捷键
- 是否显示最小化窗口
- 额外的窗口标题排除规则
- 开机启动（Launch at Login）
- 辅助功能权限状态

Altp 会自动隐藏已知的非用户窗口；用户在 Settings 中添加的标题排除规则仍可单独管理。

## 系统要求与权限

- macOS 13 Ventura 或更高版本
- 当前预编译版本仅支持 Apple silicon（`arm64`）
- 需要辅助功能权限，才能读取窗口列表并激活目标窗口

Altp 启动时不会静默申请辅助功能权限，而是先在应用内说明用途。点击 `Retry` 或 `Request Permission` 后，macOS 才会显示系统授权提示。也可以手动前往：

**系统设置（System Settings）→ 隐私与安全性（Privacy & Security）→ 辅助功能（Accessibility）**

## 常见问题

<details>
<summary><strong>为什么 Dock 里看不到 Altp？</strong></summary>

Altp 是菜单栏 App。请在菜单栏中找到 `Altp`，或直接使用已配置的快捷键。

</details>

<details>
<summary><strong>为什么无法开启开机启动？</strong></summary>

退出 Altp，把 `Altp.app` 移到 `/Applications`，然后重新打开。从“应用程序”文件夹以外的位置运行时，Altp 会主动禁用登录项注册。

</details>

<details>
<summary><strong>已经开启辅助功能权限，但仍然无法读取或切换窗口怎么办？</strong></summary>

确认 **系统设置 → 隐私与安全性 → 辅助功能** 中启用的是 `/Applications/Altp.app`，然后重启 Altp。如果之前使用过签名不同的开发版本，请删除旧的 Altp 权限条目，再重新添加当前 App。

</details>

<details>
<summary><strong>为什么某个窗口没有显示？</strong></summary>

检查 **Settings → General** 中的最小化窗口选项和标题排除规则。部分第三方窗口不会通过 macOS 辅助功能 API 稳定暴露，因此无法稳定、准确地识别和列出。

</details>

<details>
<summary><strong>下载版本支持 Intel Mac 吗？</strong></summary>

当前预编译版本仅支持 Apple silicon。源码工程面向 macOS 13，可以在受支持的开发环境中本地构建，但目前没有发布官方 Intel 二进制文件。

</details>

## 从源码构建

需要：

- Xcode Command Line Tools
- Swift 5.9 或更高版本
- 默认构建需要 `Apple Development` 或 `Developer ID Application` 签名证书

构建签名后的 App：

```bash
./scripts/build_app.sh
```

产物位于 `dist/Altp.app`。运行：

```bash
open dist/Altp.app
```

本地构建会依次尝试 `Apple Development` 和 `Developer ID Application` 证书，以保持 App 身份稳定，避免 macOS 把每次重新构建都视为新的辅助功能客户端。如果两种证书都不可用，构建默认会失败；可以显式允许临时退回 ad-hoc 签名：

```bash
ALTP_ALLOW_ADHOC=1 ./scripts/build_app.sh
```

运行回归测试：

```bash
./scripts/verify_quick_switch_layout.sh
./scripts/verify_window_ranking.sh
./scripts/verify_window_catalog.sh
```

默认 Bundle ID 是 `com.miracleagi.altp`。图标源文件位于 `assets/`；重新生成打包图标：

```bash
swift scripts/generate_icon.swift
```

<details>
<summary><strong>维护者发布流程</strong></summary>

公开分发需要 `Developer ID Application` 证书、Hardened Runtime 和 Apple 公证。

首次使用前保存公证凭据：

```bash
xcrun notarytool store-credentials altp-notary \
  --apple-id <apple-id> \
  --team-id <team-id> \
  --password <app-specific-password>
```

构建、签名、公证、写入票据并打包：

```bash
ALTP_DEVELOPER_ID_IDENTITY="Developer ID Application: Your Name (<team-id>)" \
ALTP_NOTARY_KEYCHAIN_PROFILE=altp-notary \
./scripts/release.sh
```

最终产物位于 `dist/release/Altp-<version>-macOS.zip`。

脚本只负责生成已公证的发布产物；提交代码、创建标签、推送以及发布 GitHub Release 仍需维护者单独执行。发布前请验证 Gatekeeper：

```bash
spctl -a -vvv -t exec dist/Altp.app
```

</details>

## 许可证

Altp 使用 [Apache License 2.0](./LICENSE)。
