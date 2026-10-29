# Codex 账号用量与本机归属调研

核验日期：2026 年 10 月 29 日。本次只做读取和方案验证，不改变看板统计口径，不切换登录，不安装 Hooks。

后续实现更新：用户已确认接入官方账号累计，现已实现累计、占比、每日活动和独立缓存，并通过真实账号验证。以下研究过程中的“待确认”描述为接入前的历史记录；本机历史分账方案仍未启用。

账号累计已有可用的官方数据源，并且两个已保存账号均只读实测成功。仅凭目前本机历史记录按账号拆分仍缺少充分身份信息，不能用账号累计或会话创建者反推。此前“账号历史累计无法读取”的判断需要更正：原来的 codex-auth 接入只覆盖额度查询，并未接入账号活动接口。

## 官方账号累计

官方 App Server 的 `account/usage/read` 返回 `summary.lifetimeTokens` 等摘要，以及可选的 `dailyUsageBuckets`。字段可以为空，因此缺失不能显示成零。[官方协议](https://learn.chatgpt.com/docs/app-server#7-token-usage-chatgpt)

本机核验使用已安装的 `codex-cli 0.165.0-alpha.1.2`。每个账号使用独立的临时 CODEX_HOME 和已有凭据快照，执行 `initialize`、`account/read`（不强制刷新）、`account/usage/read`。没有启动模型任务；原凭据文件读取前后的哈希保持一致，临时凭据已清理。

| 样本 | 认证 | 累计 Token | 每日活动桶 |
| --- | --- | --- | --- |
| 已保存账号 A | ChatGPT | 非空整数 | 非空数组 |
| 已保存账号 B | ChatGPT | 非空整数 | 非空数组 |

公开仓库只保存上述匿名结果，不保存真实账号名、具体用量、账号标识和凭据。

接入建议是给账号后端增加独立的 AccountActivity 读取接口。分别保存累计、日桶、服务端数据日期和本次查询时间；不与额度快照共用“更新时间”。优先走官方 App Server，不直接解析网页或依赖实验性私有资料接口。本次没有将该后端接入生产界面，待产品口径确认。

服务端账号活动与本机日志属于不同范围。官方仓库已有用户报告活动统计滞后；这是用户报告，不能当作所有账号必然延迟的产品承诺。本次返回数组末尾的日桶日期为 10 月 27 日，因此也不适合把它直接当成 Mac 本地 10 月 29 日的实时用量。[问题记录](https://github.com/openai/codex/issues/25479)

`codex-usage-analyzer` 已采用这个官方读取入口；其可选完整资料功能另行标为实验性，基本用量读取不需要那条路径。另一个独立的原生 `kexinOvO/CodexBar` 也使用 App Server 读取账号和用量。[analyzer](https://github.com/postmelee/codex-usage-analyzer)、[原生应用](https://github.com/kexinOvO/CodexBar)

## 本机历史用量归属

官方协议的 SessionMeta 源码明确说明 `creator_account_id` 是创建会话时选择的账号，恢复会话时不会更新。新的 `TokenUsageRecord` 带有 thread、turn、session、response 标识和用量，但该结构没有逐请求消费账号字段。因此创建账号只能作为历史归集线索，不能直接当成每次请求的收费身份。[协议源码](https://github.com/openai/codex/blob/main/codex-rs/protocol/src/protocol.rs)

本机只读检查也与此一致：state_5.sqlite 的 threads 表存在 creator_user_id / creator_account_id；近期 8 个会话样本尾部的 token_count 记录没有账号字段。未保存或导出聊天正文。

还验证了 `account/usage/read` 的可选 `threadId` 参数。本机 schema 和上游实现均支持会话级估算用量；两个账号对同一个近期会话的查询都成功返回响应，但 `threadUsage` 均为空。上游实现会将部分不可访问或未找到情况映射为空，所以不能将空值解释成零消耗，也不能据此判定会话属于哪个账号。[请求处理](https://github.com/openai/codex/blob/main/codex-rs/app-server/src/request_processors/account_processor.rs)、[后端会话用量](https://github.com/openai/codex/blob/main/codex-rs/backend-client/src/client/thread_usage.rs)

即便以后返回会话总量，仍需验证它是否按实际消费账号隔离，以及是否有足够的日期或请求粒度；不能仅凭“这个账号能读取会话”就完成本机今日分账。

## 可行方案与边界

| 方案 | 能解决什么 | 不能保证什么 |
| --- | --- | --- |
| 官方账号累计与日桶 | 每个账号的服务端活动总量和占比 | 限定这台电脑；与本地今天实时一致 |
| 按创建账号估算历史 | 对部分旧会话提供有标签的估算视图 | 中途换号后的准确分账 |
| 今后使用独立 CODEX_HOME | 在受控 CLI / App Server 启动方式下，让账号、凭据和会话记录分开 | 自动迁移旧历史；桌面客户端现有启动方式的兼容性 |
| 今后记录请求身份 | 在可核验运行账号、请求和时间边界时，建立真实分账记录 | 单靠监控 auth.json 或 Hooks 就完全可靠 |

官方列明 CODEX_HOME 是 CLI、IDE 扩展和 App Server 的配置、认证及会话根目录。独立目录是有依据的候选路线；桌面客户端的具体支持、继承配置和实际切换行为仍需单独验证，不能直接声称已兼容。[环境变量说明](https://learn.chatgpt.com/docs/config-file/environment-variables)

已有成熟工具也区分两种范围：steipete/CodexBar 的账号额度独立读取，本机 Token / cost 历史另行扫描；ccusage 的 Codex 数据源聚合本地日志，并处理重放、分叉和压缩用量，不把本地总量当成账号服务端统计。[CodexBar 数据源](https://github.com/steipete/CodexBar/blob/main/docs/codex.md)、[ccusage 本地统计](https://github.com/ccusage/ccusage/blob/main/docs/guide/codex/index.md)

## 下次确认的产品决定

建议先接入“账号累计”，使用已经验证可用的官方数据，右侧占比以所列账号累计之和为分母。它可以替换目前的“本机累计”，但标题和口径应一同改变，不能把官方总量塞进本机累计中。

今日区域继续使用真实本机记录。若要使用官方每日活动，就应明确改成账号活动视图，并展示服务端数据日期；若保留“本机今日”，账号归属需要等待新记录方式，不能用服务端每日总量去按比例分摊。

历史创建者估算、独立目录和请求身份记录三条路线先不启用，待确认接受的精度和使用方式后再做集成。

## 已完成的界面调整

菜单栏恢复成单个 18 点的额度进度环，数字置于圈内；仍优先使用当前配置账号的 5 小时窗口，没有时使用每周窗口。面板按内容高度调整，移除底部的填充空白。

设置改成通用、账号、提醒、高级四页。账号页左侧选择账号，右侧编辑；登录切换和 Hooks 的说明折叠保留，原有退出条件不变。

明细改成概览、当前会话、统计说明三页。默认显示两个总量和会话排行，不再用长篇说明占据首屏。当前会话采用紧凑的数据行，说明另页查看。

34 项自动测试通过，两个架构的安装包构建完成。深浅色界面已用合成数据离屏渲染检查；Mac 锁屏后不能完成原生窗口点击验收，解锁后还需确认分页、窗口高度和菜单栏环在真实桌面的显示。预览仅用于界面检查，正常启动继续读取真实数据。
