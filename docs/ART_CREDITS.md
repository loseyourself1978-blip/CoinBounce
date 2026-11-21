# 美术素材来源（ART CREDITS）

## 兔女郎角色（v11.7 起使用）

| 文件（原名） | 用途（角色系统槽位） |
|---|---|
| `01_avatar.png`（1254×1254） | headshot：老虎机兔女郎符号、头像 |
| `02_standing.png`（1024×1536） | idle：站立 |
| `03_cheer.png`（1024×1536） | cheer：双手举起欢呼 |
| `04_clap.png`（1024×1536） | clap：拍手 |
| `05_wave_alternative.png`（1024×1536） | 挥手；用在 blow-kiss（飞吻）槽位 |
| `06_jump.png`（1024×1536） | jump：跳起 |

- 来源：hj 用 ChatGPT 生成；hj 确认可以合法使用（2026-11-08）。
- 原始文件保存在本地 `~/Downloads/兔女郎素材/`，App 里用的是裁边、缩放后的版本（Asset Catalog）。
- 内容：成年女性动漫角色，经典兔女郎服装（黑色连体衣、兔耳、黑丝袜），无裸露、无性暗示动作；符合 App Store 审核指南 1.1.4。老虎机符号只用头像的面部到领结。

### v13 起：3D 风格的新图

- 2026-11-21 hj 按「3D 渲染、可爱 + 性感」的要求用 ChatGPT 重新生成了 6 张（待机、欢呼、拍手、挥手、跳、头像），原始文件在本地 `~/Downloads/兔女郎素材/3d/`。
- App 里用的是裁掉透明边、缩到 1200 高的版本（头像裁到脸和领结，512×512），素材名不变（`BunnyIdle`、`BunnyCheer`、`BunnyClap`、`BunnyBlowKiss`（挥手）、`BunnyJump`、`BunnyHeadshot`）。
- 内容要求和原来一样：成年角色、经典兔女郎服装、无裸露、无性暗示动作。

## 财神（v13.1 起使用，老虎机「财神到」）

- 2026-11-22 hj 用 ChatGPT 生成了 6 张 3D 渲染风格的财神（拱手、挥手、举手欢呼、半身头像、捧元宝、站立），透明底，原始文件在本地 `~/Downloads/兔女郎素材/caishen/`。
- App 里用的是裁掉透明边、缩到 1100 高的版本（头像 800 高）：`CaishenGreet`、`CaishenWave`、`CaishenCheer`、`CaishenHead`、`CaishenIngot`、`CaishenIdle`。
- 财神是公有领域的民间神祇形象，这一版是原创生成的造型，没有照搬任何现成游戏或影视里的角色。

## 国王与王后（v12 / 1.1 起使用）

| 素材名 | 尺寸 | 用途 |
|---|---|---|
| `KingIdle` | 1024×1024 | 国王待机（朝右），替换勇士 |
| `KingAttack` | 1024×1024 | 国王攻击（朝右） |
| `KingVictory` | 1024×1024 | 国王胜利（可选） |
| `QueenCry` | 1024×1024 | 王后哭泣（朝左），站在 BOSS 身后 |
| `QueenHappy` | 1024×1024 | 王后开心（朝左） |
| `KingQueenKiss` | 1536×1024 | K.O. 后王后亲吻国王脸颊 |

- 来源：Claude 原创的矢量图，用代码绘制后渲染成透明 PNG，没有使用任何外部素材或图片生成模型。
- 生成脚本：`tools/art/draw_king_queen.py`（输出 SVG），`tools/art/render_svg.js`（Playwright 渲染成 PNG）。改姿势或表情只需改脚本重新渲染。
- 同一角色各姿势用同一画布和比例，脚底在 y≈975（国王）和 y≈970（王后），方便对齐。

## BOSS（v12 / 1.1 起使用）

| 素材名 | 尺寸 | 用途 |
|---|---|---|
| `BossIdle` | 1024×1024 | BOSS 待机（朝左），狞笑、举着狼牙锤，替换代码绘制的 BOSS |
| `BossHurt` | 1024×1024 | BOSS 受击（朝左），闭眼后仰、冒汗，每次命中时短暂显示 |
| `BossKO` | 1024×1024 | BOSS 被击倒（朝左），坐地晕眩、螺旋眼、头顶星星、狼牙锤掉落 |

- 来源：Claude 原创的矢量图，用代码绘制后渲染成透明 PNG，没有使用任何外部素材或图片生成模型。
- 生成脚本：`tools/art/draw_king_queen.py` 里的 `boss(pose)` 和 `head_boss(...)`（输出 SVG），`tools/art/render_svg.js`（Playwright 渲染成 PNG）。
- 设计：保留原 BOSS 的特征（品红色圆头、金色犄角、獠牙），画成和国王、王后同一画风的 Q 版魔王；头身比国王大约 1.2 倍。三个姿势用同一画布和比例，脚底在 y≈975。

## 其他图形

金币、水果、老虎机符号、勇士、机台、按钮等都是代码绘制的原创图形（SwiftUI / SceneKit；BOSS 自 v12.4 起改用上面的图片），见 `docs/ASSET_LICENSES.md`。
