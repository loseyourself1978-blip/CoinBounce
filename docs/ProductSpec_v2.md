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
