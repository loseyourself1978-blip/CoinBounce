# 隐私说明与 App Store 隐私标签

> 本文是开发阶段的整理，供上架填写参考，不构成法律意见。提交审核前请对照 Google 最新的
> 「[Google Mobile Ads SDK 数据披露](https://developers.google.com/admob/ios/privacy/data-disclosure)」
> 和 AdMob 后台的实际设置再核对一遍；以后接入其他 SDK 时必须同步更新本文和 `PrivacyInfo.xcprivacy`。

## App 自身

- **本地存储**：只用 UserDefaults 保存游戏进度（金币、水果、看广告次数）和设置开关，数据不离开设备。
  - 隐私清单 required reason：`NSPrivacyAccessedAPICategoryUserDefaults` → `CA92.1`（只在本 App 内读写）。
- **账号**：没有账号、登录或服务器。
- **网络**：只有广告 SDK 会联网。

## 广告（Google Mobile Ads + UMP）

- **启动顺序**：先走 UMP 同意流程（欧盟/英国等地区会弹同意表单）→ ATT 授权（`NSUserTrackingUsageDescription`）→ 初始化 SDK → 加载激励广告。
- 用户可以在「设置 → 广告隐私选项」修改同意选择；只有在地区规定要求时才显示这个入口。
- 用户拒绝 ATT 时，SDK 不使用 IDFA，仍可能展示非个性化广告。

## App Store Connect 隐私标签建议填写

「是否收集数据」选 **是**。以下数据由广告 SDK 收集：

| 数据类型 | 用于追踪 | 与身份关联 | 用途 |
|---|---|---|---|
| 标识符 → 设备 ID（IDFA，用户同意 ATT 时） | 是 | 否 | 第三方广告、分析 |
| 使用数据 → 广告数据 | 是 | 否 | 第三方广告 |
| 使用数据 → 产品交互 | 否 | 否 | 第三方广告、分析 |
| 位置 → 粗略位置（由 IP 推断） | 否 | 否 | 第三方广告 |
| 诊断 → 崩溃数据 | 否 | 否 | 分析 |
| 诊断 → 性能数据 | 否 | 否 | 分析 |
| 诊断 → 其他诊断数据 | 否 | 否 | 分析 |

App 本身不收集：联系信息、健康、财务、通讯录、用户内容、浏览/搜索记录、敏感信息、精确位置。

## 隐私清单

- `ios/CoinBounce/PrivacyInfo.xcprivacy`：`NSPrivacyTracking = true`，声明上表的数据类型和 UserDefaults 的 required reason。
- Google Mobile Ads / UMP 的 Swift 包自带隐私清单，里面包括它们的追踪域名，构建时由 Xcode 汇总，App 清单里不需要重复。

## 上架前待办

- [x] 正式 App ID `ca-app-pub-9469890002230148~5839128885` 已填入（见 `docs/ADMOB.md`）
- [ ] 激励广告单元 ID：在 AdMob 创建后填入 `AppConfig.productionRewardedAdUnitID`
- [ ] 上架后在开发者网站根域名放 `app-ads.txt` 并在 AdMob 验证应用（见 `docs/ADMOB.md`）
- [ ] 在 AdMob 后台为 GDPR/US 州隐私法配置同意消息（UMP）和 IDFA 说明消息
- [x] 隐私政策：https://loseyourself1978-blip.github.io/CoinBounce/privacy.html （`gh-pages` 分支，已填入 `AppConfig.privacyPolicyURL`）；上架时填到 App Store Connect
- [x] 支持页（Support URL）：https://loseyourself1978-blip.github.io/CoinBounce/
- [ ] 按上表填写 App Store Connect 隐私标签
- [ ] 在 AdMob 后台把 App 关联到 App Store 上架信息，并按要求配置 app-ads.txt
