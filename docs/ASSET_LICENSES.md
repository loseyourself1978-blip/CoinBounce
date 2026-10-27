# 素材来源与许可证

本文件记录工程中每个第三方或生成素材的来源、作者和许可证。新增素材时必须同步更新。

## 音频（`ios/CoinBounce/Audio/`）

全部由本仓库的脚本 `tools/audio/generate_audio.py` 程序化合成：只用 Python 标准库的正弦、方波、三角波、噪声和包络生成，没有使用任何第三方采样或录音。随机数使用固定种子，每次运行输出相同。

- 作者：CoinBounce 项目（由 Claude Code 编写生成脚本）
- 许可证：项目自有原创素材，可商用，无第三方许可证要求
- 重新生成：`python3 tools/audio/generate_audio.py`

| 文件 | 用途 | 来源 |
|---|---|---|
| `sfx_coin_drop.wav` | 投币 | 程序合成（金属撞击泛音 + 噪声） |
| `sfx_baffle_hit.wav` | 金币碰格挡 | 程序合成（三角波短音） |
| `sfx_fruit_lit.wav` | 水果点亮 | 程序合成（C6-E6-G6 正弦和弦） |
| `sfx_bed_drop.wav` | 金币被推落 | 程序合成（多枚金币撞击叠加） |
| `sfx_slot_spin.wav` | 老虎机开始转动 | 程序合成（渐快方波棘轮声） |
| `sfx_slot_stop.wav` | 老虎机停轴 | 程序合成（低频撞击 + 咔哒） |
| `sfx_win_small.wav` | 小奖 | 程序合成（C 大调琶音） |
| `sfx_win_big.wav` | 大奖 | 程序合成（琶音 + 和弦） |
| `sfx_jackpot.wav` | Jackpot | 程序合成（三段琶音 + 和弦 + 金币闪音） |
| `sfx_button_tap.wav` | 按钮点击 | 程序合成（下滑正弦短音） |
| `sfx_no_coins.wav` | 金币不足 | 程序合成（下行两音方波） |
| `bgm_loop.wav` | 背景音乐（8 小节循环，112 BPM） | 程序合成（原创旋律、贝斯、琶音） |

## 图片与图形

**全部为代码原创，没有使用 emoji、图片素材或第三方美术资源。**

| 内容 | 来源 |
|---|---|
| App 图标 `AppIcon.appiconset/AppIcon.png`（1024×1024，无透明通道） | `tools/icon/make_icon.swift` 用 CoreGraphics 绘制生成（`swift tools/icon/make_icon.swift` 可重新生成）；替换了来源不明的 `app_logo.jpg` |
| 金币、7 种水果、9 种老虎机符号、勇士、BOSS、SPIN 图标、Jackpot 标题框 | `ios/CoinBounce/UI/ArcadeArt.swift`，SwiftUI 矢量形状 + 渐变 |
| 推币台、老虎机外框、战斗区、按钮等界面元素 | SwiftUI 代码绘制 |

- 作者：CoinBounce 项目（由 Claude Code 编写）
- 许可证：项目自有原创作品，可商用
- 文字使用 iOS 系统字体（SF Pro / 苹方）渲染，不随 App 分发字体文件。
