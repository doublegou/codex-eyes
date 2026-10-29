# 架构

## 三部分

1. `CodexEyesCore`：账号 DTO 和可用状态、串行辅助程序封装、退出检测、增量日志索引、Hooks 配置与最小事件记录。
2. `CodexEyes`：主线程状态模型、SwiftUI 看板和设置、AppKit 菜单栏与悬浮面板、系统快捷键、通知和 FSEvents。
3. `CodexEyesHook`、`scripts/`、`ThirdParty/`：被动事件接收程序、可复现的依赖获取和打包。

## 数据流

`codex-auth JSON -> AccountBackend -> AccountList -> AppModel -> DashboardView`

账号命令统一使用一个串行队列，stdout 解析 JSON，stderr 不保留。用稳定 `account_key` 定位账号。查看状态独立于配置状态，运行客户端身份在没有可靠核验接口时保持 unknown。UI 请求使用 generation 隔离演示／真实模式的延迟响应，刷新期间不并发更改账号。

`session JSONL + passive hook events -> LogIndex -> LocalSnapshot -> local-session cards / charts`

日志读取在 actor 上串行执行。每文件记录 inode、完整行偏移和累计基线，尾部半行留待后续；大行有界跳过。按会话、时间和 token 快照去重，归档和复制不重复计数。子会话的早于创建时间的重放只建立基线；缺少重放时第一条使用 latest request 避免父会话累计量被计入。计数器回退建立新基线。

FSEvents 对目录变化做防抖；未变化文件只检查元数据，不重读正文。不扫描整个用户磁盘。七日统计按用户当前日历与时区聚合。压缩标记只计算次数，不虚构缺失的压缩 token 费用。

`UsageBreakdown` 将同一日期范围的总量、账号分项和未归属记录一起汇总，未知或已移除账号的记录仍包含在分母中。`UsageDelta.accountKey` 是可选的逐事件核验标识；现有日志读取器没有可靠的逐请求身份来源，因此不填此字段，当前真实数据全部保留为未归属。不会把 session_meta 的 creator_account_id / creator_user_id 或当前 auth.json 配置当作消耗账号。UI 对未确认分项显示横线，不显示零；有部分已核验用量时以 ≥ 标明下限。开发合成数据只验证分布展示，不代表真实分账已打通。

Hooks 是同步、限时一秒的本地观察器，返回空 JSON，不批准、拒绝或修改任何调用。只记录 session ID、事件名称、接收时间和项目末级目录名。配置修改持有本应用锁、生成唯一备份、原子写回，移除时只删除带本应用标记的处理器。

## 状态与刷新

官方账号活动由 `CodexAccountActivityBackend` 通过已有 Codex CLI 的 App Server 读取。每次查询按稳定 user/account 组合选择登录快照，使用独立的 0700 临时 CODEX_HOME 与 CODEX_SQLITE_HOME，0600 凭据副本不保留刷新令牌；仅调用 initialize、account/read 和 account/usage/read。不复制用户配置，不执行登录、退出或模型任务，结束及失败均终止子进程并清理临时目录。

JSON-RPC 在专用串行队列运行，响应有超时和大小上限，stderr 与原始错误不持久化。输出仅保留官方摘要、日桶和本次读取时间；数值、日期、重复日期及溢出均检查。每日日期保持服务端原值，不按 Mac 时区重新分桶。

AppModel 的 activities 按稳定账号标识保存，独立使用 account-activity.json 缓存。刷新失败保留该账号原快照及错误；移除账号后裁剪缓存。账号累计只汇总当前列出的账号，缺少任一累计时显示部分小计并隐藏占比；零值与空字段区分。它与本机今日日志、本机七天趋势是不同数据源，不参与日志归属推断。

五分钟周期刷新、唤醒刷新、打开面板距上次检查超过一分钟刷新。过期重置快照单次立即刷新，后续交由周期定时器退避。`lastConfirmedAt` 与上游 `updated_at` 分开：值相同的成功查询也能确认新鲜度。

401 / missing_auth 表示需要登录；403 和网络错误不伪装成登录失效。没有额度窗口、过期快照、已到重置时间的旧值不会标为可用。接口正常返回单个有效窗口的套餐按实际窗口判断，不强制要求两个窗口。通知初始任务快照不触发历史提醒，额度按账号／窗口去重。

## 构建与验证

`scripts/test.sh` 运行合成数据测试。`scripts/package.sh universal` 构建两个架构并内置固定原生辅助程序。预览由真实 SwiftUI 视图通过 `--render-preview <absolute.png> [--dark]` 导出，可视检查与运行时共用界面。

账号昵称从本地登录快照的 ID token 中读取 name，按稳定 user/account 组合匹配，只用于展示，不作为授权判断。正常启动忽略历史 demo 偏好。任务名称优先使用 session_index.jsonl 中的 thread_name，缺少时回退为目录名。
