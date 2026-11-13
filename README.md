# Tart agent VMs

在 Apple Silicon 的 Mac 上用 [Tart](https://tart.run) 跑 Ubuntu 虚拟机，常驻运行
**Raft Computer**、**Claude Code**（`claude -p`）和 **GitHub CLI**，并带 Rust 与 TiUP 工具链。
**一台 Mac 可以同时装多套互相独立的虚拟机。** 所有操作通过一个脚本 `./vm` 完成。

- 隔离：每套是独立的 Linux 虚拟机（Virtualization.framework），不是共享内核的容器。
- 管理：用 `tart exec` 进入客户机，不需要 SSH、IP 或密码。
- 可复制：脚本、配置和认证步骤都固定下来，`./vm deploy` 一条命令复制到另一台 Mac。

## 要求

- Apple Silicon，macOS 13 或更新（在 macOS 26 上开发和测试）。
- 要自动启动的话，该用户需要登录在 Mac 的桌面上。
- 能访问 GitHub（下载 Tart 和镜像）、`cdn.raft.build`、`claude.ai`。

## 快速开始

```bash
git clone <this-repo> ~/tart-vm && cd ~/tart-vm
./vm install-tart                       # 下载 Tart 到 ./bin，不需要 brew 或 sudo
./vm doctor                             # 检查这台 Mac
./vm new dev --raft /myserver           # 创建一套叫 dev 的虚拟机配置
./vm -n dev init                        # 克隆镜像、设 CPU/内存/磁盘、安装软件（约 10 分钟）
```

然后做三项认证，都要你在浏览器里批准一次：

```bash
./vm -n dev raft-setup      # Raft：device code
./vm -n dev claude-login    # Claude：打开网址，把 code 粘贴回来
./vm -n dev github-login    # GitHub：device code
./vm -n dev autostart on    # 登录 macOS 后自动启动
./vm -n dev status          # 检查
```

只有一套时可以省略 `-n dev`。

## 多套虚拟机

每套是 `instances/<名字>.env` 一个文件，叠加在 [defaults.env](defaults.env) 之上。

```bash
./vm new web --raft /myserver --cpu 4 --memory 12288 --disk 100
./vm new build --raft /myserver --memory 16384
./vm list                     # 全部实例、状态、资源、是否自启
./vm -n web init
./vm -n build init
./vm use web                  # 设默认实例，之后可省略 -n
./vm -n all status            # 对全部实例执行（status start stop restart provision autostart raft-upgrade）
VM=build ./vm shell           # 也可以用环境变量选择
```

每套实例互相独立：

| 项 | 每套各一份 |
|---|---|
| 虚拟机与磁盘 | Tart 虚拟机名默认等于实例名，数据在 `~/.tart/vms/<名字>` |
| 主机名 | 新克隆的客户机主机名设为实例名 |
| Raft | 各自配对，在 Raft 里显示为 `<这台 Mac 的名字>-<实例名>` |
| Claude / GitHub | 各自登录，互不共享凭据 |
| 开机自启 | launchd 任务 `com.tartvm.<名字>` |
| 日志 | `logs/<名字>.log` |

**容量规划**：CPU 默认给每套全部核心，多套同时跑只是互相分享，没问题。
内存不同：客户机用过的内存不会还给 macOS，所以同时运行的各套 `MEMORY_MB` 之和不要超过物理内存。
`./vm new`、`init`、`set-mem` 和 `./vm doctor` 在总和超过 85% 时会警告。
Apple 对 macOS 客户机限制同时 2 台，这里只用 Linux 客户机，已实测 2 套同时运行。

## 认证

三项都在客户机里保存凭据，重启后保留。命令会在需要时打开终端交互，
`./vm` 检测到终端会自动接上，不需要 SSH。

**Raft**：`./vm -n <名字> raft-setup`
相当于 `raft-computer setup <RAFT_SERVER> --name <名字> --no-start`，成功后启用 systemd 服务。
终端会打印 device code 和网址：在浏览器登录 Raft，输入 code，选服务器，点 Add to Server。
命令保持运行，它在你批准后自动结束。撤销：`./vm raft detach <RAFT_SERVER>`。

**Claude**：`./vm -n <名字> claude-login`
终端打印一个网址。在浏览器登录并授权，把页面给的 code 粘贴回终端。
也可以用 `claude-key` 保存 `ANTHROPIC_API_KEY`（按 API 计费，优先于账号登录）
或 `claude setup-token` 生成的 `CLAUDE_CODE_OAUTH_TOKEN`，写入客户机 `~/.config/raft-vm/env`（权限 600）。
验证：`./vm claude -p "say hi"`。

**GitHub**：`./vm -n <名字> github-login`
先按回车接受 `Authenticate Git with your GitHub credentials? (Y/n)`，再把打印的 code 填到
https://github.com/login/device 授权。组织启用了 SAML SSO 的话，对该组织点 Authorize。
完成后 git 自动使用这个登录，并在没有身份时设置提交者名字和邮箱。
也可以用 `github-token` 提供个人访问令牌。令牌以明文保存在客户机 `~/.config/gh/hosts.yml`。

## 磁盘、CPU、内存

```bash
./vm -n dev set-disk 300     # 扩到 300 GB，只增不减
./vm -n dev set-cpu 8        # 不带参数 = 全部核
./vm -n dev set-mem 28672    # MB
```

- 这些命令会先优雅关机，修改后再启动，并写回实例文件。
- 扩盘后客户机开机时自动扩展根分区，不需要手工 `growpart`。
- 磁盘是稀疏镜像，Mac 只占实际写入量，但客户机删文件后镜像不会自动缩小。`~/.tart/vms/<名字>` 可能很大。
- Tart 的 “GB” 是十进制：200 GB 约 186 GiB，客户机里 `df` 约 180G 可用。
- 客户机已调高 `vm.max_map_count`、inotify 和文件描述符上限（登录 shell 里 `ulimit -n` 为 524288），适合 TiKV。

## 开机启动

`./vm -n <名字> autostart on` 安装 launchd 用户代理：

- 登录 macOS 后启动虚拟机，客户机里的 systemd 随后启动 Raft Computer。
- 虚拟机崩溃会自动拉起。`./vm stop` 后保持停止，直到你 `./vm start` 或这台 Mac 重启。
- 登出或关机时先让客户机 `poweroff` 再退出，避免丢数据。

这是**登录时**启动，不是**开机未登录**时启动，因为 Virtualization.framework 需要用户的图形会话。
想断电重启后无人值守恢复，在“系统设置 > 用户与群组”开启自动登录（需关闭 FileVault）。

## 复制到另一台 Mac

```bash
./vm deploy user@192.168.0.20            # 目标目录默认与本地目录同名（在对方的 home 下），可作第二个参数
```

它用 rsync 复制脚本，在对方装好 Tart，并复制 `instances/` 里对方还没有的实例文件，不会覆盖已有的。
然后在对方机器上对每套实例运行 `init` 和三项认证。认证与虚拟机数据不复制，每台机器各自独立。

也可以直接在对方机器上 `git clone` 这个仓库，再 `./vm new`。

## 日常维护

| 想做的事 | 命令 |
|---|---|
| 看全部 / 看一套 | `./vm list` / `./vm -n <名字> status` |
| 进入虚拟机 / 跑命令 | `./vm shell` / `./vm run <cmd...>` |
| 启动 / 停止 / 重启 | `./vm start` / `stop` / `restart` |
| Raft 状态、体检、日志 | `./vm raft status` / `raft doctor` / `raft-logs [-f]` |
| 升级 Raft Computer | `./vm raft-upgrade` |
| 升级 Claude Code | `./vm claude update` |
| 重新安装依赖 | `./vm provision`（幂等，可重复） |
| 升级 Tart | `./vm install-tart --force` |
| 删除一套 | `./vm -n <名字> destroy --purge` |

`destroy` 要求输入实例名确认，`--purge` 同时删除 `instances/<名字>.env`。

Raft Computer 以 systemd 用户服务 `raft-computer` 运行（`raft-computer start --foreground`），
`Restart=always`，PATH 包含 `~/.local/bin`、`~/.cargo/bin`、`~/.tiup/bin`。

## 目录结构

| 路径 | 作用 | 是否提交 |
|---|---|---|
| `vm` | 管理脚本 | 是 |
| `defaults.env` | 所有实例的默认值 | 是 |
| `instances/example.env` | 实例模板 | 是 |
| `instances/<名字>.env` | 你的实例配置（`./vm new` 生成） | 否 |
| `guest/provision.sh` | 在客户机内执行的初始化脚本，幂等 | 是 |
| `guest/raft-computer.service` | Raft Computer 的 systemd 用户单元 | 是 |
| `bin/` | 本机 Tart 二进制 | 否 |
| `logs/`、`.state/` | 日志；默认实例、“已手动停止”标记 | 否 |

## 从旧版升级

旧版只有一个 `config.env`。第一次运行新的 `./vm` 时会自动把它转成 `instances/<VM_NAME>.env`，
设为默认实例，并保留旧 launchd 任务依赖的两个设置，所以已安装的自启任务无需改动、虚拟机不会重启。
想用新的任务标签和日志位置，运行一次 `./vm -n <名字> autostart on`（会重启该虚拟机），然后删掉实例文件末尾的迁移说明和两行设置。

## 已知限制

- 三项浏览器授权需要你亲自完成，脚本无法代劳。
- `tart stop` 是强制断电，所以脚本一律先在客户机里 `poweroff`；不要直接用 `tart stop`。
- 强杀 Tart 进程或断电时，最近约 40 秒内写入的文件可能变成 0 字节（ext4 延迟分配），已用 `sync=fsync` 缩小窗口。需要停机一律用 `./vm stop`。
- 客户机内存不会还给 macOS，直到虚拟机关机。
- Tart 版本由 `install-tart` 下载最新发行版，许可条款见 `bin/TART-LICENSE`。
