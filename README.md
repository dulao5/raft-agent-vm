# raft-agent-vm

简体中文 | [English](README.en.md) | [日本語](README.ja.md)

基于 [Tart](https://tart.run) 在 Apple Silicon Mac 上快速创建并管理多套隔离的 Ubuntu 虚拟机，专为常驻运行 AI 编程代理与开发工具链而设计。所有生命周期管理、环境配置、认证与文件传输均通过单一脚本 `./vm` 完成。

## 核心特性

- **硬件级隔离**：基于 Apple `Virtualization.framework` 运行独立的 Linux 虚拟机，而非共享内核的容器。
- **免 SSH 管理**：通过 `tart exec` 与客户机代理通信，无需配置 SSH 密钥、IP 地址或密码。
- **单机多实例**：一台 Mac 可同时运行多套相互独立的虚拟机，各自拥有独立的主机名、磁盘、凭据与自启服务。
- **开箱即用的工具链**：内置自动化脚本，一键安装 **Raft Computer**、**Claude Code**、**Antigravity CLI**、**GitHub CLI**、**Rust** 与 **TiUP**，并预设适用于 TiKV / `tiup playground` 的内核与文件描述符参数。
- **可复制部署**：通过 `./vm deploy` 一键将脚本与实例配置同步至另一台 Mac。

## 虚拟机预装环境

执行 `./vm init` 或 `./vm provision` 后，客户机内会自动安装并配置以下组件（幂等，可重复执行）：

- **AI 代理与编排**：[Raft Computer](https://raft.build)（以 systemd 用户服务常驻运行）、[Claude Code](https://claude.ai)（`claude`）、[Antigravity CLI](https://antigravity.google)（`agy`）
- **开发工具链**：GitHub CLI（`gh`）、Rust 工具链（`rustup`）、TiUP（`tiup`）
- **基础构建依赖**：`build-essential`、`clang`、`cmake`、`pkg-config`、`libssl-dev`、`protobuf-compiler`、`git`、`tmux`、`jq`、`ripgrep`、`python3` 等
- **系统调优**：调高 `vm.max_map_count`（1,048,576）、`fs.inotify.max_user_watches`（1,048,576）、`fs.file-max`（4,194,304）以及 `nofile` 限制（1,048,576）

## 环境要求

- **硬件与系统**：Apple Silicon Mac，macOS 13 或更高版本
- **桌面会话**：如需启用开机自启，对应用户需登录至 macOS 图形桌面会话
- **网络访问**：能够访问 GitHub（下载 Tart 与基础镜像）、`cdn.raft.build`、`claude.ai`、`antigravity.google`

## 快速开始

### 1. 克隆仓库并检查环境

```bash
git clone https://github.com/dulao5/raft-agent-vm.git
cd raft-agent-vm

./vm install-tart                       # 下载 Tart 到 ./bin（无需 Homebrew 或 sudo）
./vm doctor                             # 检查系统架构、macOS 版本与内存余量
```

### 2. 创建并初始化虚拟机

```bash
./vm new dev --raft /myserver           # 创建名为 dev 的实例配置
./vm -n dev init                        # 克隆镜像、配置硬件资源并安装软件（首次约 10 分钟）
```

> 当仅存在一个实例，或已通过 `./vm use <name>` 设置默认实例时，后续命令可省略 `-n <name>`。

### 3. 完成服务认证并启用自启

各服务需在浏览器中完成一次授权，凭据将持久化保存在客户机内：

```bash
./vm -n dev raft-setup      # 配对 Raft Computer 并启动后台服务
./vm -n dev claude-login    # 登录 Claude Code
./vm -n dev agy auth        # 登录 Antigravity CLI（可选）
./vm -n dev github-login    # 登录 GitHub CLI 并配置 Git 凭据
./vm -n dev autostart on    # 启用 macOS 登录自动启动
./vm -n dev status          # 检查虚拟机与各服务运行状态
```

## 多实例管理

每个实例对应 `instances/<name>.env` 中的一个配置文件，其设置会覆盖 [defaults.env](defaults.env) 中的全局默认值。

```bash
./vm new web --raft /myserver --cpu 4 --memory 12288 --disk 100
./vm new build --raft /myserver --memory 16384
./vm list                     # 查看所有实例的状态、资源配置与自启状态
./vm -n web init
./vm -n build init

./vm use web                  # 设为默认实例（之后可省略 -n）
VM=build ./vm shell           # 也可通过环境变量临时指定实例
./vm -n all status            # 批量操作所有实例
```

> `-n all` 支持的子命令：`status`、`start`、`stop`、`restart`、`provision`、`autostart`、`raft-upgrade`。

### 实例隔离范围

| 项目 | 隔离方式 |
|---|---|
| 虚拟机与磁盘 | Tart 虚拟机名称默认与实例名一致，磁盘镜像位于 `~/.tart/vms/<name>` |
| 主机名 | 首次克隆时自动将客户机主机名设为实例名 |
| Raft 节点名 | 各自独立配对，在 Raft 中显示为 `<Mac 名称>-<实例名>` |
| 账号凭据 | Claude、Antigravity、GitHub 凭据均保存在各自客户机内，互不共享 |
| 开机自启 | 独立的 launchd 任务 `com.tartvm.<name>` |
| 宿主机日志 | 独立记录于 `logs/<name>.log` |

### 资源规划建议

- **CPU**：默认分配宿主机全部逻辑核心，多个运行中的虚拟机可安全共享 CPU。
- **内存**：Linux 客户机已使用的内存不会在运行期间归还给 macOS，请确保**同时运行**的实例 `MEMORY_MB` 总和低于宿主机物理内存。当所有已配置实例的内存总和超过宿主机物理内存的 85% 时，`new`、`init`、`set-mem` 和 `doctor` 会输出警告。
- **并发数量**：Apple 对同时运行 2 台虚拟机的限制仅针对 macOS 客户机，Linux 客户机不受此限制，仅受宿主机硬件资源约束。

## 服务认证说明

所有认证命令均在交互式终端下自动接管输入输出，无需 SSH，凭据保存于客户机内并在重启后保持有效。

### Raft Computer

```bash
./vm -n <name> raft-setup
```

执行 `raft-computer setup <RAFT_SERVER> --name <RAFT_COMPUTER_NAME> --no-start`，终端会输出 device code 与授权链接。在浏览器登录 Raft 并完成确认后，脚本将自动启用并启动 systemd 用户服务 `raft-computer`。

- 如需解绑：`./vm -n <name> raft detach <RAFT_SERVER>`

### Claude Code

- **账号登录**：运行 `./vm -n <name> claude-login`，打开终端输出的授权链接并将授权码粘贴回终端。
- **密钥 / Token 登录**：运行 `./vm -n <name> claude-key`，按提示存入 `ANTHROPIC_API_KEY`（API 计费，优先级高于账号登录）或 `CLAUDE_CODE_OAUTH_TOKEN`（通过 `claude setup-token` 生成）。凭据以 `600` 权限写入客户机 `~/.config/raft-vm/env`。清除已存密钥可使用 `./vm -n <name> claude-key clear`。
- **验证**：`./vm -n <name> claude -p "say hi"`

### Antigravity CLI（可选）

```bash
./vm -n <name> agy auth
```

命令会启动交互式 `agy` 引导登录：选择 **Google OAuth**（或 **Use a Google Cloud project**），在浏览器完成授权并将授权码粘贴回终端；出现输入框即表示登录成功，连续按两次 `Ctrl+C` 退出。脚本会自动校验登录状态并重启 `raft-computer` 服务使代理生效。

- 由于客户机环境不包含桌面钥匙串（Secret Service），`~/.profile` 与 `raft-computer.service` 均配置了 `AGY_CLI_FORCE_FILE_TOKEN_STORAGE=1`，令牌以文件形式持久化保存。
- **验证**：`./vm -n <name> agy -p "say hi"`
- **退出登录**：运行 `./vm -n <name> agy` 后输入 `/logout`。

### GitHub CLI

- **浏览器登录**：运行 `./vm -n <name> github-login`，按提示确认 Git 凭据集成，并在 https://github.com/login/device 输入一次性验证码（若组织启用了 SAML SSO，请为对应组织点击 Authorize）。
- **PAT 登录**：运行 `./vm -n <name> github-token` 并粘贴 Personal Access Token。
- 认证完成后会自动配置 `git` 凭据，并在未设置全局 Git 身份时自动填充 `user.name` 与 `user.email`。凭据保存在客户机 `~/.config/gh/hosts.yml`。

## 资源调整与文件传输

### 调整 CPU、内存与磁盘

```bash
./vm -n dev set-disk 300     # 扩容虚拟磁盘至 300 GB（只增不减）
./vm -n dev set-cpu 8        # 设置 CPU 核心数（省略参数恢复为全部核心）
./vm -n dev set-mem 28672    # 设置内存（单位：MB）
```

- 调整命令会自动优雅关闭虚拟机、应用新配置、重新启动，并将变更写回 `instances/<name>.env`。
- 磁盘扩容后，客户机在下次启动时自动扩展根分区，无需手动执行 `growpart`。
- 虚拟磁盘为稀疏镜像，宿主机仅占用实际写入空间；但客户机内删除文件后镜像不会自动收缩。
- Tart 的磁盘容量按十进制 GB 计算（例如 200 GB 约等于 186 GiB）。

### 宿主机与客户机文件传输

使用 `./vm cp` 在宿主机和客户机之间复制文件或目录（支持目录递归传输，并以 SHA-256 校验完整性）：

```bash
# 宿主机 -> 客户机（以 : 开头表示客户机路径，相对路径基于客户机 $HOME）
./vm cp ./local.txt ./mydir :~/work/

# 客户机 -> 宿主机（目标路径默认为当前目录 .）
./vm cp :~/work/output.log .
```

## 开机自动启动

```bash
./vm -n <name> autostart on    # 启用
./vm -n <name> autostart off   # 关闭
```

启用后会安装 launchd 用户代理（`~/Library/LaunchAgents/com.tartvm.<name>.plist`）：

- 登录 macOS 桌面后自动拉起虚拟机，客户机内的 systemd 随之启动 `raft-computer`。
- 虚拟机意外崩溃时自动重启；通过 `./vm stop` 手动停止后则保持关闭，直至手动 `./vm start` 或重启宿主机。
- 登出或关机时，先向客户机发送 `systemctl poweroff` 优雅关机，再退出进程，降低数据损坏风险。

> 由于 `Virtualization.framework` 依赖用户的图形会话，自启发生在**登录桌面后**而非开机登录界面。如需在断电重启后无人值守恢复，可在 macOS「系统设置 > 用户与群组」中开启自动登录（需关闭 FileVault）。

## 部署到另一台 Mac

```bash
./vm deploy user@192.168.0.20 [remote-dir]
```

该命令通过 `rsync` 同步脚本与默认配置，在目标机器上安装 Tart，并复制目标机器上尚不存在的实例配置文件（不会覆盖已有配置）。随后在目标 Mac 上对相应实例执行 `init` 与服务认证即可。虚拟机镜像与凭据不会跨机器复制。

## 常用命令速查

| 场景 | 命令 |
|---|---|
| 查看所有实例 / 单个实例详情 | `./vm list` / `./vm -n <name> status` |
| 进入交互式 Shell / 执行单条命令 | `./vm shell` / `./vm run <cmd...>` |
| 复制文件进 / 出虚拟机 | `./vm cp <src...> :<dst>` / `./vm cp :<src> [dst]` |
| 启动 / 停止 / 重启 | `./vm start` / `./vm stop` / `./vm restart` |
| 查看 Raft 状态、自检、日志 | `./vm raft status` / `./vm raft doctor` / `./vm raft-logs [-f]` |
| 升级 Raft Computer | `./vm raft-upgrade` |
| 升级 Claude Code / Antigravity CLI | `./vm claude update` / `./vm agy update` |
| 重新执行客户机配置（幂等） | `./vm provision` |
| 升级宿主机 Tart | `./vm install-tart --force` |
| 彻底删除实例与磁盘 | `./vm -n <name> destroy --purge` |

> `destroy` 需输入实例名二次确认；附加 `--purge` 会同时删除对应的 `instances/<name>.env`。

## 目录结构

| 路径 | 说明 | Git 跟踪 |
|---|---|---|
| [vm](vm) | 主管理脚本 | 是 |
| [defaults.env](defaults.env) | 全局默认实例配置 | 是 |
| [instances/example.env](instances/example.env) | 实例配置模板 | 是 |
| `instances/<name>.env` | 实际实例配置（由 `./vm new` 生成） | 否 |
| [guest/provision.sh](guest/provision.sh) | 客户机初始化与依赖安装脚本（幂等） | 是 |
| [guest/raft-computer.service](guest/raft-computer.service) | Raft Computer 的 systemd 用户服务单元 | 是 |
| `bin/` | 本机下载的 Tart 二进制与许可文件 | 否 |
| `logs/`、`.state/` | 宿主机运行日志；默认实例与手动停止状态标记 | 否 |

## 注意事项与已知限制

- **浏览器授权**：Raft、Claude、Antigravity 与 GitHub 的 OAuth / Device Code 流程均需在浏览器中手动确认。
- **优雅关机**：`tart stop` 等同于强制断电，请始终使用 `./vm stop` 关闭虚拟机（脚本会先触发客户机 `poweroff`）。
- **异常断电风险**：若强杀 Tart 进程或宿主机意外断电，ext4 延迟分配可能导致最近数十秒内写入的文件截断为 0 字节。脚本默认启用 `--root-disk-opts=sync=fsync` 以缩小数据丢失窗口；如需更严格的一致性，可在配置中设为 `DISK_OPTS=sync=full`（会降低 fsync 密集型操作性能）。
- **内存回收**：虚拟机运行期间已分配的内存不会归还给 macOS，直到虚拟机关机。
- **Tart 许可**：`./vm install-tart` 会下载最新官方发行版，其许可条款保存在 `bin/TART-LICENSE`。
