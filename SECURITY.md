# 安全策略 (Security Policy)

## 支持的版本 (Supported Versions)

本项目仅支持 `main` 分支。所有安全更新均通过该分支发布。

| 分支 | 支持状态 |
|------|----------|
| main | ✅ 活跃支持 |
| 其他分支 | ❌ 不支持 |

## 报告安全漏洞 (Reporting Security Issues)

**请勿为安全漏洞创建公开 Issue。**

如果你发现本项目存在安全问题，请直接联系维护者进行报告。报告中**不要**包含任何 API key、token、密码或其他敏感凭据。

请通过以下方式联系：
- 在 GitHub 上私信（Direct Message）项目维护者
- 通过维护者邮箱直接联系

我们会尽快确认并回复你的报告，并在修复后公开致谢（除非你要求匿名）。

## Secret 处理策略 (Secret Handling Policy)

本项目**从不**存储、传输或处理任何 API key、token 或凭据。具体而言：

- 安装脚本（install.sh）不会写入任何 secret
- 项目文件中不包含任何硬编码的凭据
- 项目不会与外部服务交换认证信息

如果你在代码库中发现了任何 secret 或凭据，请立即按照上述方式报告。这是一个严重问题，我们会优先处理。

## 安装脚本安全性 (Installer Safety)

`install.sh` 的行为范围如下：

- ✅ 将 skill 文件复制到 `~/.hermes/skills/` 目录
- ❌ 不修改系统文件
- ❌ 不安装全局 package
- ❌ 不修改 PATH 环境变量
- ❌ 不修改任何 environment variable

**建议：** 在正式执行前，始终先使用 `--dry-run` 参数预览安装过程：

```bash
./install.sh --dry-run
```

## 免责声明 (No Warranty)

本项目按 **MIT License** 提供，**不附带任何担保**。

使用本项目的风险完全由使用者自行承担。维护者不对因使用本项目而产生的任何直接或间接损失负责。

## 数据收集 (Data Collection)

本项目**不收集、不传输、不存储**任何用户数据。具体而言：

- 无 analytics（无分析数据采集）
- 无 telemetry（无遥测数据上报）
- 无 phone-home（无回传机制）
- 无任何形式的用户行为追踪

## 第三方依赖 (Third-party Dependencies)

本项目的运行时依赖为**零**。

整个项目仅由以下内容组成：

- Markdown 文件（skill 定义、文档）
- Bash 脚本（安装脚本）

不引入任何第三方 library、framework 或 package，从根本上消除了供应链攻击风险。
