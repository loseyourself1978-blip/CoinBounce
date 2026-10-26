# 金币勇士大闯关（Coin Bounce）

iOS 推币机休闲游戏，基于 SwiftUI + SpriteKit，最低支持 iOS 16。玩法以推币机为核心，融合老虎机、弹珠台、打砖块等小游戏。

当前版本见 [`PROJECT_VERSION.json`](PROJECT_VERSION.json)。

## 目录结构

```
.
├── ios/
│   ├── CoinBounce/              # App 源码
│   │   ├── App/                 # 入口
│   │   ├── GameCore/            # 常量、状态、触感
│   │   ├── CoinPusher/          # 推币机场景
│   │   ├── SlotMachine/         # 老虎机
│   │   ├── Pinball/             # 弹珠台
│   │   ├── Breakout/            # 打砖块
│   │   ├── UI/                  # SwiftUI 界面与设计 Token
│   │   └── Assets.xcassets/     # 图片资源
│   ├── CoinBounceTests/         # 单元测试
│   └── CoinBounce.xcodeproj
├── docs/
│   ├── ProductSpec_v2.md        # 产品说明（与 PROJECT_VERSION.spec_version 对齐）
│   ├── UI_Design_System.md      # UI 设计系统 v4
│   ├── ACCEPTANCE_STANDARD.md   # 验收标准
│   ├── CHANGELOG.md
│   ├── VERSIONING_RULES.md
│   └── game_constants.md
├── tools/acceptance/            # iOS 截图对比验收脚本
├── scripts/                     # 模拟器运行、验收流水线脚本
├── build_ios.sh                 # 编译 + 单元测试
└── PROJECT_VERSION.json         # 版本单一来源
```

## 构建与测试

需要 Xcode（含 iOS 模拟器），默认使用 iPhone 17 模拟器：

```bash
cd ios
xcodebuild -scheme CoinBounce -destination 'platform=iOS Simulator,name=iPhone 17' build
xcodebuild -scheme CoinBounce -destination 'platform=iOS Simulator,name=iPhone 17' test
```

或在仓库根目录运行 `./build_ios.sh`（编译并跑单元测试）。

## 版本规则

每次通过验收的迭代都要升级版本号，详见 [`docs/VERSIONING_RULES.md`](docs/VERSIONING_RULES.md)。

## 资料归档

参考素材（样例截图、录屏、视频帧）、历史产品文档（.docx）、早期 H5 原型、过程报告、旧验收流水线等不放在仓库中，已归档到本机：

`~/Downloads/CoinBounce_资料归档/`（目录内有 `索引.md`）

依赖归档内容的脚本：

- `tools/acceptance/run_ios_acceptance.sh` 需要参考图 `samples/ref_400x880.png`。归档位置为 `CoinBounce_资料归档/参考素材/samples/ref_400x880.png`，运行前把它复制到仓库根目录的 `samples/`（该目录已被 .gitignore 忽略）。
- `scripts/acceptance_full_run.sh` 调用的旧验收流水线 `acceptance/` 已归档到 `CoinBounce_资料归档/参考素材/acceptance/`，需要时复制回仓库根目录。
