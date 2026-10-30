# 从源码构建

需要 macOS 14+、Xcode 26+（含 macOS 26+ SDK）、Python 3（仅构建时）。App 本身不依赖 Node.js 或 Python。官方账号统计还需要可用的官方 Codex CLI（须支持 account/usage/read）；程序会检测 ChatGPT / Codex App 内置路径及常见安装路径。

```sh
bash scripts/test.sh
python3 scripts/test-account-import.py # 下载固定辅助程序后可运行的离线导入检查
bash scripts/package.sh arm64
open 'dist/Codex Eyes.app' --args --show
```

Intel 使用 `bash scripts/package.sh x86_64`；通用包使用 `bash scripts/package.sh universal`。依赖下载检查固定 SHA-512；辅助程序固定为 codex-auth 0.3.1，不自动追踪上游主分支。

开发时可以 `python3 scripts/vendor.py` 后 `swift run CodexEyes --show`。打包后的 App 才支持开机启动和完整 Hooks 路径。

正常启动始终加载真实账号和本机日志，不恢复旧版本保存的演示模式。开发者可显式传 `--demo` 或 `--render-preview` 使用合成数据进行布局验证；该模式不保存在偏好中，公开使用界面不提供演示开关。README 中的预览图片使用合成数据，真实账号画面不提交仓库。


打包与签名见[发行流程](releasing.md)，设计与数据分层见[架构](architecture.md)。
