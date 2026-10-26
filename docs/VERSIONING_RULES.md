# 版本管理规则（必须遵守）

## 1. 版本源

- **单一事实来源**：`PROJECT_VERSION.json`
- **代码 tag**：`v<version>`（例如 `v9.5.1`）
- **文档版本**：所有产品/视觉规范文档的“版本记录”必须引用同一个 `version`

## 2. 版本更新触发

只要满足任一条件，就必须 bump `version`：

- UI/视觉有可见变化（像素、布局、颜色、动效）
- 物理/手感参数变化（重力、摩擦、碰撞、推子、概率）
- 玩法/奖励规则变化
- 测试用例新增/调整
- 构建/验收脚本变化

## 3. 对应关系（强制）

- `PROJECT_VERSION.json.version` ↔ git tag `v<version>`
- `ProductSpec_v2.md`（或后续 spec）必须记录该版本对应的关键改动、验收截图/视频、测试结果链接（Web报告路径）
- 自动化验收报告必须写入本次 `version` 与 git commit sha

