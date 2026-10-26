# CoinBounce 变更记录（代码/文档版本对齐）

> 规则：
> - 每次“可验收”的改动都必须：
>   - 更新 `PROJECT_VERSION.json` 的 `version`
>   - 更新相关产品/视觉规范文档中的版本表
>   - 更新/新增自动化测试用例
>   - 通过 `build_ios.sh`（以及后续的完整验收脚本）
> - 代码 tag 使用 `v<version>`，文档中也使用同一版本号。

## v9.5.0 (2026-04-20)

- **基线**：引入 `PROJECT_VERSION.json`、`.gitignore`、`docs/CHANGELOG.md`，用于后续迭代的版本/回滚管理。

## v9.5.1 (2026-04-20)

- **验收流水线**：新增 `tools/acceptance/` 自动化验收（跑单测→启动模拟器→截图→按区域对照参考图生成 Web 报告）。

## v9.5.2 (2026-04-20)

- **对齐迭代（进行中）**：推币台区域改用资源图 `coin_pusher_ref` 作为底图；投币按钮改为六边形并居中，新增箭头引导（由 `showTutorialArrow` 控制）。

