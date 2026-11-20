# AGENTS.md — MuMuGuard 开发强制规则

> 本文件是给后续维护者（包括 AI 助手）的开工检查表。**每次开始工作前先读对应规则文件**。

## 开工前（强制）

- 修 BUG：先读 [`docs/BUGFIX-RULES.md`](docs/BUGFIX-RULES.md)，按里面的定位 → 修改 → 验证 → 发布流程执行。
- 加功能：先读 [`docs/FEATURE-RULES.md`](docs/FEATURE-RULES.md)，按设计 → 实现 → 兼容 → 回归流程执行。
- 两个文件末尾的「事故档案 / 警钟」也要看，避免重复踩坑。

## 铁律（摘要）

1. **先看后改**：读完整调用链、全局搜索字段/函数名，确认根因再动代码；一次只修一个根因，不顺手重构。
2. **不破坏旧功能**：改公共函数/字段/口径前，列出全部消费者（UI、手机端、告警、持久化、测试），同步修改并逐项回归。
3. **必须用 exe 发布版验证**：`build\release.ps1` 编译出的 exe 在真实实例上验证，禁止只跑脚本版就宣布完成。
4. **纯逻辑进 `lib\90-pure.ps1` 并补单测**；UI 线程不做 WMI/IO 重活；后台线程显式传参。
5. **PowerShell 5.1**：每个 `.ps1` 必须有 UTF-8 BOM；无 `Join-String`；`$i:` 要写 `${i}:`；改完先 `Check-BOM.ps1 -Fix`。
6. **数据安全**：不删用户数据；改动第三方软件配置前先备份并征得用户同意；不伪造鼠标/键盘输入。
7. **如实报告**：验证证据、残留风险、未覆盖项都要写清楚。

## 版本号与公告

- 修复：只改末尾数字（`2.1.1 → 2.1.2`）；公告/发布说明写「修复了一些问题」。
- 加功能：改中间位数、末位归 0（`2.1.1 → 2.2.0`）；公告简单写加了什么。
- 公告与发布说明只保留代码库和群号，其他从简。

## 发布前检查（每次）

1. `Check-BOM.ps1 -Fix` → `Check-BOM.ps1`
2. `tests\Check-Syntax.ps1`
3. `tests\Run-Tests.ps1` 全过（新逻辑要有单测）
4. `build\release.ps1`（含 smoke test，自检项必须全 PASS）
5. exe 实机验证 + 回归清单
6. `git` 提交（写清根因/改动/影响面/验证证据）
7. `_build\push-via-api.ps1` 推送 master 和 tag
8. `gh release create v<版本>` 上传 exe / sha256 / 源码 zip，核对 digest

## 项目速查

- 主程序：`MuMuGuardApp.ps1`；模块在 `lib\`（加载顺序见主脚本「加载模块」段：`90-pure` 最前，`00-common` … `63-res`）
- 数据目录：`_dist\`（exe 与脚本版共用 `config.json` / `sleep.json` / `trend.json` / `logs` / `shots`）
- 配置读取：`Initialize-Config`；迁移版本 `ConfigVersion`；设置生效：`Apply-SettingSideEffect`
- 采集：`Get-InstanceData`（进程内存 = `MuMuNxDevice` + `MuMuVMMHeadless`）
- 打包：`build\release.ps1`（bundle + PS2EXE + smoke test + 源码 zip + sha256）
- 推送：`_build\push-via-api.ps1`（GitHub HTTPS 直推被墙时的 API 方案，会建 tag）
- 仓库：`github.com/suuk324/MuMuGuard`；QQ 群：`1128379535`