# Arcade Coin Pusher - Product Specification (v8.0.0)

## 0. Version History & Code Linkage
> 代码/文档版本对齐：见仓库根目录 `PROJECT_VERSION.json`（`version` 为统一版本号，`spec_version` 对应本文件）。

| Version | Date | Iteration | Key Changes |
| :--- | :--- | :--- | :--- |
| v2.0.0 | 2026-04-11 | Iteration 5 | Initial Full-Screen Sync, 3D Slopes, 5 Baffles. |
| v6.0.0 | 2026-04-14 | Iteration 6 | Side-drops, 10+ Baffles, Slot Expansion, Pusher Physics. |
| **v8.0.0** | 2026-04-14 | **Iteration 8** | Physics Anti-Lag, Z-Stacking Refinement, Correct Drop Origin Sync. |

## 1. Overview
The Arcade Coin Pusher app is a 2.5D physical replication of the classic arcade pusher format. This specification outlines all spatial and mechanical layout targets defined iteratively from test feedback loops.

## 2. Global Layout Coordinates
* The screen height distributes perfectly into 100% accumulation layers to avoid overlapping components hiding beneath safe areas.
* `Padding(.horizontal)` clipping around full-width layers MUST NOT exceed 2-4 points on internal content otherwise pure black bounding rectangles appear.

## 3. Physical Synchronicity Rules
1. **Red Coin Slider Engine**: Operates dynamically tracking physical amplitude `= UIScreen.main.bounds.width * 0.45`.
2. **Coin Drop (Iteration 6)**: Coins drop from the **left/right sides** of the 52px slider alternatingly, rather than the center.
3. **2D Physical Renderer**: The `Coin2DRenderLayer` ignores safe areas natively. Coins must calculate visual scale origins relative to `-geo.size.width * 0.45` bounds natively.

## 4. UI Elements & Sizes
* **Gold Coin (Iteration 6)**: Rendered at `28x28` scale. Visuals: Metallic gold gradient, 3D depth shadow, internal "$" or "★" pattern.
* **Fruit Lights**: Arranged in an array of exactly 7 components: `["🍎", "🍎", "🍇", "⭐", "🔔", "🍉", "🍌"]`.
* **Bonus Marker**: Floating visual slider.
    - **Size**: Reduced by 30% from Iteration 5.
    - **Position**: Anchored `0.5 * radius (7px)` below the Fruit Row bar.
* **Slot Matrix**: Full width 5-column expansion. Icons must fill horizontal space to eliminate gaps between reel dividers.

## 5. Geometry Deflection (Baffles & Hurdles)
* **Battle Scene Area**: 5 solid metallic pins.
* **Slot Machine Area (Iteration 6)**: 10 Additional baffles placed at:
    - Reel top centers (middle 3).
    - Reel divider centers (4 vertical gold lines).
    - Reel bottom centers (middle 3).

## 6. Isometric Slopes (Green Ramps)
* **Direction (Iteration 6)**: Slopes must angle inward. Outer edges are "high", guiding coins toward the central pusher bed.
* Slopes are generated using customized multi-layered Poly Shapes to mimic real depth perception.

## 7. Pusher Bed Physics (Iteration 6)
* Coins on the bed respond to `pusherOffset`. Increasing density triggers horizontal "squeezing" forces, pushing outer coins off the ledge into the 3D zone.

## 版本记录

| 版本 | 日期 | 关键改动 | 验收 |
|---|---|---|---|
| 10.5.0 | 2026-10-27 | 推币台撑满屏宽、下落金币不旋转、老虎机只由 BONUS 触发（排队）、水果一轮约 40 枚 | 106 个单元测试通过；截图 `~/Downloads/CoinBounce_资料归档/截图_v10.5.0/` |
| 10.6.0 | 2026-10-27 | 按参考比例调整布局（老虎机 27%、推币台叠在投币按钮下）、老虎机格挡、2D/3D 金币大小一致、滑块和推板减速、3D 感增强 | 113 个单元测试通过；截图 `~/Downloads/CoinBounce_资料归档/截图_v10.6.0/` |
| 10.7.0 | 2026-10-28 | 侧板完整显示、斜坡移到推板上方（外高内低）、推板全部收回刮币、金币变薄加浮雕、水果从中间穿过点亮、帮助页、前沿竖直截面、BONUS 立体牌、暗紫金推板 | 117 个单元测试通过；截图 `~/Downloads/CoinBounce_资料归档/截图_v10.7.0/` |
| 10.8.0 | 2026-10-28 | 去掉两侧侧板、推币区域与下落区同宽（相机自动求解）、投币按钮贴底、首次投币金色箭头引导、金币古铜金与更低机位 | 全部单元测试通过；截图 `~/Downloads/CoinBounce_资料归档/截图_v10.8.0/` |
| 11.0.0 | 2026-11-01 | 推币台物理重建：金币堆铺到推板最远处、推板真正推动金币堆并从前沿掉落、不再丢弃新币；斜坡改实心楔形块；金币直径 +30% 厚度不变 | 125 个单元测试（含真实物理测试）通过；录屏 `~/Downloads/CoinBounce_资料归档/录屏验证_v11.0.0/` |
| 11.1.0 | 2026-11-01 | 按参考逐帧测量重排布局（各区域屏幕位置误差 < 1%）、两侧立柱 10%、中间窄推板 + 两侧绿色斜坡 + 接币盘、底部金色面板、深紫老虎机、方形水果牌 | 全部单元测试（含真实物理）通过；录屏 `~/Downloads/CoinBounce_资料归档/录屏验证_v11.1.0/` |
| 11.2.0 | 2026-11-01 | 无缝交接（同模型渲染、同位置同大小）、只保留一块斜坡、金币堆 2 层、前沿掉落全程可见、下落 1.75 秒、BONUS 区装饰、拱形投币口、6 项画面验收门槛 | 全部单元测试通过（含 60 秒真实窗口画面门槛）；录屏 `~/Downloads/CoinBounce_资料归档/录屏验证_v11.2.0/` |
| 11.3.0 | 2026-11-02 | 金币从投币口到接币槽全程 3D（无 2D→3D 交接）；下半部机器按新参考录屏逐部件测量、反投影摆放（误差 1–2 像素）；全屏透明 3D 视图；参考帧叠加调试工具 | 119 个测试通过（含结构门槛和 60 秒真实窗口物理门槛）；录屏 `~/Downloads/CoinBounce_资料归档/录屏验证_v11.3.0/` |
| 11.3.1 | 2026-11-02 | 补回 v11.3 删除测试的等价检查（8 个）；60 秒门槛去掉误报（连续性用物理时间、停住物理再读统计）；台面两侧沿屏幕边缘加透明墙，金币不再从侧面跑出画面 | 128 个测试通过（全套最后连续 2 次全部通过） |
| 11.4.0 | 2026-11-02 | 上半部按新参考逐框对齐（整屏比例、隐藏状态栏）：JACKPOT 大牌、金币 / 按钮一行、投币口拱门和 COIN 牌、老虎机机柜和转轴窗口、战斗区、水果排；结构门槛加入上半部；下落 1.75 秒 ±10% | 128 个测试通过；截图 `~/Downloads/CoinBounce_资料归档/截图_v11.4.0/`、录屏 `录屏验证_v11.4.0/` |
| 11.5.0 | 2026-11-03 | 金币更亮更金、BONUS 立体牌与边框闪光、等边六边形投币按钮、推币台加宽（台阶贴屏幕边、两侧落币槽归机器）、推板完全收回（顶面金币一个周期内掉下）、屏幕常亮、发热降级、性能优化 | 131 个测试通过；60 秒门槛连续 3 次全绿；截图 `~/Downloads/CoinBounce_资料归档/截图_v11.5.0/`、录屏 `录屏验证_v11.5.0/` |
