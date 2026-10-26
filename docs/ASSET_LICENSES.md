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

## 图片

| 文件 | 来源 | 许可证 |
|---|---|---|
| `AppIcon.appiconset` | 待补充（上架前确认来源或替换为原创图标） | 待确认 |

推币台、老虎机、战斗区等界面元素全部由 SwiftUI 代码绘制，没有使用图片素材。表情符号（🍎、👺 等）由系统字体渲染。
