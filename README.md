# tat — Tips And Todo

[![CI](https://github.com/QAQDFAFD/tat/actions/workflows/ci.yml/badge.svg)](https://github.com/QAQDFAFD/tat/actions/workflows/ci.yml)
[![Release](https://img.shields.io/github/v/release/QAQDFAFD/tat)](https://github.com/QAQDFAFD/tat/releases)
[![License: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)

屏幕右边缘的一张便签：**今天要做的事 + 今天值得瞄一眼的事。**

一个极简的 macOS 原生小工具。平时完全不占界面，鼠标碰到屏幕最右侧时滑出，移开自动收起；需要时可以「钉住」常驻。

- **Todo**：只有「添加」和「完成」。回车添加，点圆圈完成；未完成的自动顺延，前一天完成的第二天自动清空。
- **Tips**：今日赛事（英超 / 西甲 / 意甲 / 德甲 / 法甲 / 欧冠 / 中超 / NBA，可选）和主要指数（上证、深证、创业板、恒生、纳斯达克100、标普500、道琼斯等，可选）。
- **不打扰**：没有 Dock 图标；悬停呼出不抢键盘焦点；面板收起时不发任何网络请求。

产品设计见 [docs/DESIGN.md](docs/DESIGN.md)。

## 安装

1. 到 [Releases](https://github.com/QAQDFAFD/tat/releases) 下载最新的 `tat-x.y.z.dmg`，把 tat 拖进「应用程序」。
2. 应用使用 ad-hoc 签名、未经 Apple 公证，首次打开前在终端执行一次：

   ```bash
   xattr -dr com.apple.quarantine /Applications/tat.app
   ```

3. 打开后菜单栏出现 tat 图标（旁边的数字是未完成待办数）。

要求 macOS 14 Sonoma 及以上，Apple 芯片和 Intel 均可。

## 使用

| 操作 | 方式 |
| --- | --- |
| 呼出面板 | 鼠标移到屏幕最右侧停留一下 · ⌥⌘T · 点菜单栏图标 |
| 收起面板 | 鼠标移开 · Esc · 再按 ⌥⌘T |
| 一直显示 | 面板右上角 📌，或菜单栏图标右键 →「常驻显示」 |
| 添加待办 | 在输入框输入，回车 |
| 完成 / 撤销 | 点左侧圆圈；已完成的在「已完成」里可撤销 |
| 删除 | 鼠标悬停行尾的 ×，或右键 →「删除」 |
| 设置 | 面板右上角齿轮：触发延迟、开机启动、指数、联赛、涨跌颜色 |

数据存放在 `~/Library/Application Support/tat/todos.json`。行情来自腾讯财经，赛事来自 ESPN，均为公开接口、仅供参考。

## 开发

```bash
brew install xcodegen
xcodegen generate        # 生成 Tat.xcodeproj（已在 .gitignore 中）
open Tat.xcodeproj
```

```
Sources/
  App/      入口、菜单栏图标、全局快捷键、设置、开机启动
  Panel/    EdgePanel 窗口 + EdgeTrigger（边缘呼出的纯逻辑状态机）
  Todo/     TodoStore：增删改、跨天规则、JSON 持久化
  Tips/     腾讯行情 / ESPN 赛事数据源、球队中文名、TipsStore
  Views/    SwiftUI 界面
Tests/      单元测试（XCTest）
UITests/    端到端测试（XCUITest，真实启动 App、模拟鼠标与键盘）
```

### 测试

```bash
# 单元测试（34 个）
xcodebuild test -project Tat.xcodeproj -scheme TatUnit -destination 'platform=macOS'

# 端到端测试：真实启动 App，模拟鼠标移到屏幕右边缘、添加/完成待办、切换设置……
# 运行期间会接管鼠标和键盘，约 1.5 分钟内请不要操作电脑。
xcodebuild test -project Tat.xcodeproj -scheme Tat -destination 'platform=macOS' -only-testing:TatUITests

# 访问真实的腾讯 / ESPN 接口（默认跳过，CI 不跑）
TEST_RUNNER_TAT_LIVE_TESTS=1 xcodebuild test -project Tat.xcodeproj -scheme TatUnit \
  -destination 'platform=macOS' -only-testing:TatTests/LiveDataTests
```

UI 测试使用 `-uiTesting` 启动参数：独立的偏好设置、临时数据目录、固定的桩数据，不访问网络，也不会改动你的开机启动项。

### CI 与发布

- **CI**（`.github/workflows/ci.yml`）：每次 push 到 `main` 和每个 PR，在 macOS runner 上跑单元测试 + 端到端测试，测试结果（含面板截图）作为 artifact 上传。
- **Release**（`.github/workflows/release.yml`）：推送 `v*` tag 自动跑单元测试、构建通用二进制（arm64 + x86_64），发布 GitHub Release 并附上 `.dmg`、`.zip` 和 `SHA256SUMS.txt`。

```bash
git tag v0.2.0
git push origin v0.2.0
```

本地打包：`scripts/build-release.sh 0.2.0`，产物在 `dist/`。

## License

[MIT](LICENSE)
