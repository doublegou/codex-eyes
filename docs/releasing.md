# 应用安装包与公开发行

Codex Eyes 是原生菜单栏应用，交付物包含完整 `.app`，不是网页或需要用户运行的脚本。
推荐通过 GitHub Releases 分发 DMG；用户打开后将 Codex Eyes 拖入“应用程序”。
不要求用户安装 Node.js、Python 或 Xcode。菜单栏仍显示当前账号额度，应用图标独立使用 `Assets/AppIcon.png`。
首次启动自动展开看板，后续可从菜单栏圆环或快捷键打开。

## 生成安装包

```sh
bash scripts/test.sh
bash scripts/package.sh universal
```

- `dist/Codex Eyes.app`：完整应用。
- `dist/CodexEyes-1.0.0-universal.dmg`：拖入“应用程序”的安装磁盘映像。
- 同名 ZIP 与 SHA-256 文件：备选下载格式与校验值。

默认使用本地签名，未经过 Apple 公证。版本名称与签名状态独立。
不建议让用户关闭 Gatekeeper 或移除隔离属性作为安装流程。

## 公开发行前

1. **图标**：当前用户提供的图片含 OpenAI Blossom，不随项目 MIT 许可证授权。
   按 [OpenAI 品牌规则](https://openai.com/brand/)，公开版需替换中央标志或取得适用授权。
   应用安装包附带图标声明；替换素材后同步更新 `Assets/NOTICE.md`。
2. **证书**：需要 Apple Developer Program 对应团队的 `Developer ID Application` 签名身份。
   `Apple Development` 是开发证书，不替代站外发行身份。
3. **公证**：在本机钥匙串配置 notarytool profile，凭据不写入代码或仓库。
4. **兼容验证**：目前已验证本机 Apple Silicon；Intel 实机、macOS 14 实机及干净用户环境仍需验收。

参考：[Developer ID 与 Gatekeeper](https://developer.apple.com/developer-id/)。

## 正式打包

```sh
export CODEX_EYES_SIGN_IDENTITY='Developer ID Application: YOUR NAME (TEAMID)'
export CODEX_EYES_NOTARY_PROFILE='YOUR_KEYCHAIN_PROFILE'
bash scripts/package.sh universal --release
```

脚本在构建前检查必要配置；未提供发行身份或公证配置时直接失败。
应用、Hook 和账号辅助程序从内到外签名，随后对应用提交公证并附加票据，
再制作、签名和公证 DMG。ZIP 包含已附加票据的应用。
最后执行 Gatekeeper 检查，通过后才视为公开包；校验值在最终文件生成后计算。
脚本不会自动创建 GitHub 仓库或上传发布。

## 用户环境与隐私

- 额度工具随 App 内置，固定 `codex-auth 0.3.1`；账号累计与官方每日活动还需要支持相关接口的 Codex CLI，
  应用会查找已安装 ChatGPT/Codex 客户端内的 CLI 及常见命令行安装位置。
- 没有登录或日志时显示空状态，不自带开发者账号、会话、缓存或凭据。
- 所有账号与统计缓存保存在用户自己的 Application Support 目录，不进入安装包。
- Hooks 是可选项；将 App 安装到最终位置后再连接。已有 Hooks 的本地预览用户移动 App 后需要重新连接。
- MIT 代码许可、codex-auth 许可及图标声明包含在 App 的 `Contents/Resources/Licenses/`。
- 本版没有自动更新、业务服务器或上报功能。
