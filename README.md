# cclaude

**让 Claude Code 在不同终端窗口同时跑不同模型。**

> 搭配 [cc-switch](https://github.com/nicepkg/cc-switch) 使用。cc-switch 负责管理你的模型供应商，cclaude 负责让它们同时在线。

## 为什么需要它

你一定遇到过这个场景——

用 cc-switch 配好了 DeepSeek、智谱 GLM、小米 MiMo 三个供应商，想在三个终端窗口里同时跑。但切换供应商是全局生效的——切到 DeepSeek，所有窗口都变成 DeepSeek。想一边让 GLM 做代码审查，一边让 DeepSeek 做功能开发？做不到。

cc-switch 解决了"管理多个供应商"的问题，但留下了一个缺口：**同一时间只能激活一个供应商**。它是一个切换器，不是一个并行器。

cclaude 从 cc-switch 的数据库中读出你所有供应商的配置，为每个供应商生成一份独立的 Claude Code 配置目录，然后通过官方的 `CLAUDE_CONFIG_DIR` 环境变量隔离启动。不修改任何全局文件，不依赖 hack，不备份恢复。

效果：

```
终端 1:  cclaude deepseek    →  DeepSeek 在跑
终端 2:  cclaude zhipu       →  智谱 GLM 在跑
终端 3:  cclaude mimo        →  小米 MiMo 在跑
```

各跑各的，互不干扰，全局配置全程不被触碰。

**一句话总结：cc-switch 让你可以切模型，cclaude 让你可以在不同终端窗口同时跑不同模型。**

## 前置条件

| 依赖 | 说明 | 检查方式 |
|------|------|----------|
| **Git Bash** | 脚本运行环境，安装 Git for Windows 时自带 | `bash --version` |
| **Python** | 读取 SQLite 数据库（自动检测 `py` / `python` / `python3`） | `py --version` 或 `python --version` |
| **Claude Code CLI** | 你要切换的那个工具 | `claude --version` |
| **cc-switch** | 管理供应商配置，cclaude 从它的数据库读取供应商信息 | 确认 `~/.cc-switch/cc-switch.db` 存在 |

> cc-switch 中需要至少一个 `app_type='claude'` 的供应商配置，且 `settings_config` 里包含 `env` 字段，否则 cclaude 无法工作。

## 安装

### 第一步：下载文件

下载 `install.ps1` 和 `cclaude.sh`，放到同一个文件夹里。比如 `Downloads\cclaude\`。

### 第二步：运行安装脚本

打开 PowerShell，进入下载目录后运行：

```powershell
先运行cd Downloads\cclaude
再运行.\install.ps1
```

安装脚本会自动完成以下检查和操作：

```
[1/6] Checking Python...       → 自动检测 py / python / python3，缺则报错
[2/6] Checking Git Bash...     → 检测 bash 是否可用
[3/6] Checking Claude Code...  → 检测 claude 命令是否可用
[4/6] Checking cc-switch...    → 检测 ~/.cc-switch/cc-switch.db 是否存在
[5/6] Installing script...     → 复制 cclaude.sh 到 ~/.cclaude/cclaude.sh
                                → 文件内容未变则跳过（Already up-to-date）
[6/6] Registering function...  → 在 PowerShell profile 中注册 cclaude 命令
                                → 已存在则更新路径，不重复添加
```

完成后自动执行首次同步，从 cc-switch 数据库读取所有供应商并生成独立配置目录。

> 以后在 cc-switch 中新增或修改了供应商，运行 `cclaude -s` 重新同步即可。

### 第三步：激活

当前 PowerShell 窗口立即生效：

```powershell
. $PROFILE
```

或者打开一个新的 PowerShell 窗口，自动生效。

### 验证安装

```powershell
cclaude -l
```

看到供应商列表即安装成功。

## 使用

### 命令一览

| 命令 | 作用 |
|------|------|
| `cclaude` | 交互菜单选择供应商，选择后启动 Claude Code |
| `cclaude <名称>` | 模糊匹配供应商名称，直接启动（不弹菜单） |
| `cclaude -l` / `--list` | 列出所有可用供应商，不启动 |
| `cclaude -s` / `--sync` | 从 cc-switch 数据库重新同步所有供应商配置 |
| `cclaude -h` / `--help` | 显示帮助信息 |

### 交互模式

不带参数运行时进入交互选择：

```
$ cclaude
Available providers:
  1. Claude Official
  2. DeepSeek
  3. 火山
  4. Xiaomi MiMo
  5. Zhipu GLM (current)
Enter number [5]:
```

- 括号里的编号对应 cc-switch 中当前激活的默认供应商
- 直接回车 = 用默认供应商启动
- 输入编号 = 选对应供应商启动

### 快捷启动

通过名称模糊匹配，不区分大小写：

```powershell
cclaude deepseek       # 匹配 "DeepSeek"
cclaude zhipu          # 匹配 "Zhipu GLM"
cclaude 火山           # 匹配 "火山"
cclaude mimo           # 匹配 "Xiaomi MiMo"
```

匹配规则：
- 匹配到唯一一个 → 直接启动
- 匹配到多个 → 提示冲突，列出所有匹配的名称
- 匹配不到 → 报错，提示用 `cclaude --list` 查看可用名称

### 多终端并行

这是 cclaude 的核心能力——在不同终端窗口同时使用不同供应商，互不干扰：

```
终端窗口 1:  cclaude deepseek    → 使用 DeepSeek
终端窗口 2:  cclaude zhipu       → 使用 智谱 GLM
终端窗口 3:  cclaude mimo        → 使用 小米 MiMo
```

每个窗口独立运行，关闭后全局配置不受影响。

### 同步供应商变更

在 cc-switch 中新增或修改了供应商后，运行一次同步：

```powershell
cclaude -s
```

会重新从数据库读取所有供应商并更新对应的配置目录。

## 工作原理

### 核心机制：CLAUDE_CONFIG_DIR

Claude Code 官方支持 `CLAUDE_CONFIG_DIR` 环境变量，用于指定自定义配置目录。cclaude 利用这一官方特性实现供应商隔离——每个供应商拥有独立的配置目录，各自读取各自的 `settings.json`，互不冲突。

### 调用链路

```
在 PowerShell 中输入 cclaude deepseek
  │
  ├─ PowerShell profile 中的 function cclaude 被调用
  │   └─ bash "C:\Users\<用户名>\.cclaude\cclaude.sh" deepseek
  │
  ├─ cclaude.sh 执行
  │   ├─ 自动检测可用的 Python 命令（py / python / python3）
  │   ├─ 读取 cc-switch SQLite 数据库中的供应商列表
  │   ├─ 模糊匹配 "deepseek" → 命中 DeepSeek 供应商
  │   ├─ 同步配置：
  │   │   ├─ 创建 ~/.claude-providers/deepseek/ 目录（如不存在）
  │   │   └─ 生成 settings.json（基于全局配置，替换 env 为 DeepSeek 的配置）
  │   ├─ 清理临时文件（含 API 密钥，确保不留在磁盘上）
  │   └─ 启动 Claude Code：
  │       CLAUDE_CONFIG_DIR=~/.claude-providers/deepseek exec claude
  │
  └─ Claude Code 运行
      ├─ 从独立目录的 settings.json 读取配置
      ├─ 全局 ~/.claude/settings.json 全程不被触碰
      ├─ 退出后独立配置目录保留（下次直接用，无需重新同步）
      └─ 其他终端窗口中的 Claude Code 实例不受影响
```

### 目录结构

安装完成后的文件布局：

```
~/.cclaude/
  cclaude.sh                        # 主脚本（由 install.ps1 安装至此）

~/.claude-providers/
  claude-official/
    settings.json                   # Claude Official 的独立配置
  deepseek/
    settings.json                   # DeepSeek 的独立配置
  xiaomi-mimo/
    settings.json                   # 小米 MiMo 的独立配置
  zhipu-glm/
    settings.json                   # 智谱 GLM 的独立配置
```

每个供应商的 `settings.json` 保留全局配置中的 `enabledPlugins`、`includeCoAuthoredBy` 等字段，只将 `env` 替换为对应供应商的 API 地址、密钥和模型信息。同时自动注入 `CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC=1` 以减少非必要网络请求。

> 供应商目录名（slug）由名称自动生成：英文转小写，非字母数字字符替换为 `-`。若名称不含 ASCII 字符（如纯中文），则使用 cc-switch 中的供应商 ID 作为目录名。

### 安全性

- **不修改全局配置** — `~/.claude/settings.json` 全程不被触碰
- **临时文件即时清理** — 包含 API 密钥的临时文件在 `exec claude` 之前删除，不残留于磁盘
- **只读 cc-switch** — 仅从 cc-switch 数据库读取数据，不做任何写入
- **per-session 隔离** — 每个终端使用独立的 `CLAUDE_CONFIG_DIR`，互不干扰

## 常见问题

### 运行 install.ps1 报错"无法加载，因为在此系统上禁止运行脚本"

PowerShell 默认限制脚本执行。用以下方式绕过：

```powershell
powershell -ExecutionPolicy Bypass -File .\install.ps1
```

或者右键 `install.ps1` → 属性 → 勾选"解除锁定"（从网上下载的文件可能需要此操作）。

### cclaude 命令找不到

确认 PowerShell profile 中已注册该函数：

```powershell
cat $PROFILE
```

应能看到 `function cclaude { ... }`。如果没有，重新运行 `.\install.ps1`。

当前窗口需要先执行 `. $PROFILE` 或打开新的 PowerShell 窗口才会生效。

### 供应商列表是空的

确认 cc-switch 中存在 `app_type='claude'` 的供应商配置，并且至少有一个供应商的 `settings_config` 中包含 `env` 字段。

### 更新 cclaude

重新下载最新的 `cclaude.sh` 和 `install.ps1`，再次运行 `.\install.ps1`。安装脚本会通过 SHA256 校验自动判断是否需要更新——文件内容未变则跳过，有变化则覆盖。

## 文件说明

| 文件 | 说明 |
|------|------|
| `cclaude.sh` | 主脚本——读取数据库、匹配供应商、生成独立配置、启动 Claude Code |
| `install.ps1` | 安装脚本——环境检测、复制脚本、注册 PowerShell 命令、首次同步 |

## 卸载

1. 从 PowerShell profile 中删除 `function cclaude { ... }` 所在行
2. 删除脚本和配置目录：

```powershell
Remove-Item -Recurse -Force "$env:USERPROFILE\.cclaude"
Remove-Item -Recurse -Force "$env:USERPROFILE\.claude-providers"
```

## License

MIT
