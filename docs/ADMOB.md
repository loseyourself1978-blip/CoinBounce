# AdMob 配置

| 项目 | 值 | 位置 |
|---|---|---|
| 发布商 ID | `pub-9469890002230148` | AdMob 后台 → 账号 |
| App ID（Coin Bounce） | `ca-app-pub-9469890002230148~5839128885` | `Info.plist` 的 `GADApplicationIdentifier`、`AppConfig.adMobAppID` |
| 激励广告单元 ID | **待补**（在 AdMob 后台创建激励广告单元后填入） | `AppConfig.productionRewardedAdUnitID` |

> 注意：`ca-app-pub-9469890002230148~6075852473` 是另一款 App「Line Reveal」的 App ID，不要用在本 App。

## 构建规则

- **Debug 构建**：始终使用 Google 官方测试激励广告单元 `ca-app-pub-3940256099942544/1712485313`，避免开发时点到正式广告被判为无效流量。
- **Release 构建**：使用正式激励广告单元。`productionRewardedAdUnitID` 还是占位值时，**不加载、不展示广告**（领币按钮隐藏，并记录日志），绝不会退回去用测试 ID 或空 ID。单元测试会检查这条规则。

## 创建激励广告单元

1. AdMob → 应用 → Coin Bounce → 广告单元 → 添加广告单元 → 激励广告（Rewarded）。
2. 奖励数量填 `50`，奖励项填 `coins`。
3. 保存后得到 `ca-app-pub-9469890002230148/…`，替换 `AppConfig.productionRewardedAdUnitID`。

## 上架后：app-ads.txt 与应用验证

AdMob 验证应用时，会检查 App Store 页面上「开发者网站」**根域名**下的 `app-ads.txt`。文件内容（一行）：

```
google.com, pub-9469890002230148, DIRECT, f08c47fec0942fa0
```

- 如果用 GitHub Pages 作为开发者网站，需要单独的用户站点仓库 `loseyourself1978-blip.github.io`，把文件放在 `https://loseyourself1978-blip.github.io/app-ads.txt`（`/CoinBounce/` 子路径下不算根域名）。
- App Store Connect 里的「营销网址 / 开发者网站」要填同一个根域名。
- 上架后在 AdMob 里把 App 关联到 App Store 页面，再点「Verify app」。
