# 自动化验收标准（以参考App为准）

## 1. 黄金参考

- **参考截图**：`samples/ref_400x880.png`
- **参考区域标注**：`samples/ref_analysis_annotated.png`
- **参考录屏**：`samples/ScreenRecording_*.{MP4,mov}`、`samples/录屏*.mov`

## 2. 自动化验收入口

运行脚本（会生成可预览的 Web 报告）：

```bash
tools/acceptance/run_ios_acceptance.sh
```

输出位置：

- `reports/acceptance/ios/<version>/index.html`

## 3. 区域对比（当前实现）

区域定义：

- `tools/acceptance/regions_ref400x880.json`

指标含义（0~255）：

- **MAE**：平均绝对误差，越小越好
- **RMSE**：均方根误差，越小越好
- **PSNR**：峰值信噪比，越大越好

## 4. 验收通过标准（阶段性）

> 最终目标是“肉眼一致”，指标仅作为收敛方向。

阶段性门槛（每次迭代逐步收紧）：

- **Stage A（先收敛结构）**：
  - `slot/battle/fruit/pusher/button` 区域 **MAE < 60**
- **Stage B（对齐材质与细节）**：
  - 关键区域（`pusher`, `button`, `slot`）**MAE < 40**
- **Stage C（接近参考App）**：
  - 全图 **MAE < 25**，关键区域 **MAE < 20**

## 5. 必测交互（自动化将逐步覆盖）

- 投币：扣币、生成金币、触觉反馈
- 格挡：老虎机格挡、水平偏转明显
- 水果：命中点亮、全亮触发卡牌
- BONUS：命中触发旋转、奖励与特效
- 推床：金币进入推床、推子推动、掉落结算

