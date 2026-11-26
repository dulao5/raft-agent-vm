# raft-agent-vm

[简体中文](README.md) | English | [日本語](README.ja.md)

Create and manage multiple isolated Ubuntu VMs on Apple Silicon Macs with [Tart](https://tart.run), purpose-built for running persistent AI coding agents and development toolchains. All lifecycle operations, provisioning, authentication, and file transfers are handled through a single `./vm` script.

## Highlights

- **True VM Isolation**: Runs independent Linux virtual machines via Apple's `Virtualization.framework`, rather than kernel-sharing containers.
- **No SSH Required**: Communicates with the guest through `tart exec` and the guest agent—no SSH keys, IP lookups, or passwords needed.
- **Multi-Instance on One Mac**: Run several independent VMs side by side, each with its own hostname, virtual disk, credentials, and autostart service.
- **Batteries-Included Guest Environment**: Idempotent provisioning installs **Raft Computer**, **Claude Code**, **Antigravity CLI**, **GitHub CLI**, **Rust**, and **TiUP**, along with kernel and file-descriptor tuning suited for TiKV / `tiup playground`.
- **Portable Setup**: Sync scripts and instance definitions to another Mac in one command with `./vm deploy`.

## What's Preinstalled in Each VM

Running `./vm init` or `./vm provision` configures the guest idempotently with:

- **AI Agents & Orchestration**: [Raft Computer](https://raft.build) (running as a persistent systemd user service), [Claude Code](https://claude.ai) (`claude`), [Antigravity CLI](https://antigravity.google) (`agy`)
- **Developer Toolchains**: GitHub CLI (`gh`), Rust toolchain (`rustup`), TiUP (`tiup`)
- **Build Essentials**: `build-essential`, `clang`, `cmake`, `pkg-config`, `libssl-dev`, `protobuf-compiler`, `git`, `tmux`, `jq`, `ripgrep`, `python3`, etc.
- **System Tuning**: Raised `vm.max_map_count` (1,048,576), `fs.inotify.max_user_watches` (1,048,576), `fs.file-max` (4,194,304), and `nofile` limits (1,048,576)

## Prerequisites

- **Hardware & OS**: Apple Silicon Mac running macOS 13 or later
- **Desktop Session**: For autostart, the user account must be logged into a macOS graphical session
- **Network Access**: Reachability to GitHub (Tart releases and base images), `cdn.raft.build`, `claude.ai`, and `antigravity.google`

## Quick Start

### 1. Clone and Verify the Host

```bash
git clone https://github.com/dulao5/raft-agent-vm.git
cd raft-agent-vm

./vm install-tart                       # Download Tart into ./bin (no Homebrew or sudo required)
./vm doctor                             # Check architecture, macOS version, and memory budget
```

### 2. Create and Provision a VM

```bash
./vm new dev --raft /myserver           # Create an instance named 'dev'
./vm -n dev init                        # Clone image, configure CPU/RAM/disk, and provision (~10 min first time)
```

> When only one instance exists—or after setting a default with `./vm use <name>`—you can omit `-n <name>`.

### 3. Authenticate Services and Enable Autostart

Each service requires a one-time browser approval; credentials are persisted inside the guest VM:

```bash
./vm -n dev raft-setup      # Pair Raft Computer and enable the background service
./vm -n dev claude-login    # Sign in to Claude Code
./vm -n dev agy auth        # Sign in to Antigravity CLI (optional)
./vm -n dev github-login    # Sign in to GitHub CLI and configure Git credentials
./vm -n dev autostart on    # Start the VM automatically on macOS login
./vm -n dev status          # Verify VM and service health
```

## Managing Multiple Instances

Each instance is defined by a single file at `instances/<name>.env`, layered on top of [defaults.env](defaults.env).

```bash
./vm new web --raft /myserver --cpu 4 --memory 12288 --disk 100
./vm new build --raft /myserver --memory 16384
./vm list                     # Show all instances, state, resources, and autostart status
./vm -n web init
./vm -n build init

./vm use web                  # Set the default instance (allows omitting -n)
VM=build ./vm shell           # Override the target instance via environment variable
./vm -n all status            # Run a command across all instances
```

> Subcommands supporting `-n all`: `status`, `start`, `stop`, `restart`, `provision`, `autostart`, `raft-upgrade`.

### Per-Instance Isolation

| Component | Isolation |
|---|---|
| VM & Disk | Tart VM name defaults to the instance name; stored under `~/.tart/vms/<name>` |
| Hostname | Automatically set to the instance name on a fresh clone |
| Raft Computer Name | Paired independently as `<Mac-name>-<instance>` |
| Credentials | Claude, Antigravity, and GitHub logins live inside each guest and are never shared |
| Autostart | Dedicated launchd agent `com.tartvm.<name>` |
| Host Logs | Written separately to `logs/<name>.log` |

### Capacity Planning

- **CPU**: Defaults to all logical host cores. Multiple running VMs share cores safely.
- **Memory**: Guest memory used by Linux is not returned to macOS while the VM is running. Keep the combined `MEMORY_MB` of **concurrently running** VMs below the host's physical RAM. `new`, `init`, `set-mem`, and `doctor` warn when configured instances exceed 85% of host memory.
- **Concurrency**: Apple's 2-VM cap applies only to macOS guests; Linux guests are limited only by host resources.

## Authentication Details

All authentication commands attach an interactive terminal automatically without SSH, and credentials persist across VM reboots.

### Raft Computer

```bash
./vm -n <name> raft-setup
```

Runs `raft-computer setup <RAFT_SERVER> --name <RAFT_COMPUTER_NAME> --no-start` and prints a device code and URL. Once approved in the browser, the script enables and starts the `raft-computer` systemd user service.

- To detach: `./vm -n <name> raft detach <RAFT_SERVER>`

### Claude Code

- **Account Login**: Run `./vm -n <name> claude-login`, open the printed URL, authorize in the browser, and paste the code back.
- **API Key / OAuth Token**: Run `./vm -n <name> claude-key` to store either `ANTHROPIC_API_KEY` (API billing, takes precedence over account login) or `CLAUDE_CODE_OAUTH_TOKEN` (generated via `claude setup-token`). Secrets are stored in `~/.config/raft-vm/env` inside the guest with mode `600`. Clear stored keys with `./vm -n <name> claude-key clear`.
- **Verify**: `./vm -n <name> claude -p "say hi"`

### Antigravity CLI (Optional)

```bash
./vm -n <name> agy auth
```

Launches an interactive `agy` session: choose **Google OAuth** (or **Use a Google Cloud project**), open the printed URL in your browser, approve, and paste the code back. Once the prompt box appears, press `Ctrl+C` twice to exit. The script verifies the login and restarts `raft-computer` so background agents pick up the credentials.

- Because the guest has no desktop Secret Service (keychain), both `~/.profile` and `raft-computer.service` set `AGY_CLI_FORCE_FILE_TOKEN_STORAGE=1` to persist the token on disk.
- **Verify**: `./vm -n <name> agy -p "say hi"`
- **Sign Out**: Run `./vm -n <name> agy` and enter `/logout`.

### GitHub CLI

- **Browser Login**: Run `./vm -n <name> github-login`, confirm Git credential integration, and enter the one-time code at https://github.com/login/device (authorize SAML SSO for your organization if applicable).
- **Personal Access Token**: Run `./vm -n <name> github-token` and paste a PAT.
- Automatically configures `git` credentials and populates global `user.name` / `user.email` if unset. Tokens are stored in `~/.config/gh/hosts.yml` inside the guest.

## Resources & File Transfer

### Resizing CPU, Memory, and Disk

```bash
./vm -n dev set-disk 300     # Grow virtual disk to 300 GB (can only grow)
./vm -n dev set-cpu 8        # Set CPU cores (omit argument for all host cores)
./vm -n dev set-mem 28672    # Set memory in MB
```

- Each command gracefully stops the VM, applies the change, restarts it, and updates `instances/<name>.env`.
- After growing the disk, the guest automatically expands its root partition on boot—no manual `growpart` needed.
- Virtual disks are sparse images: macOS only allocates space actually written, though deleting files inside the guest does not automatically shrink the image.
- Tart measures disk sizes in decimal GB (200 GB ≈ 186 GiB).

### Copying Files To and From the Guest

Use `./vm cp` to transfer files or directories (recursive for directories, verified with SHA-256):

```bash
# Host -> Guest (prefix guest paths with ':'; relative paths resolve from guest $HOME)
./vm cp ./local.txt ./mydir :~/work/

# Guest -> Host (destination defaults to '.')
./vm cp :~/work/output.log .
```

## Autostart on Login

```bash
./vm -n <name> autostart on    # Enable
./vm -n <name> autostart off   # Disable
```

Installs a launchd user agent (`~/Library/LaunchAgents/com.tartvm.<name>.plist`):

- Starts the VM on macOS desktop login; systemd inside the guest then starts `raft-computer`.
- Automatically restarts the VM after unexpected crashes, while keeping it stopped after `./vm stop` until you run `./vm start` or reboot the Mac.
- On logout or shutdown, cleanly powers off the guest via `systemctl poweroff` before exiting.

> Because `Virtualization.framework` requires a graphical user session, autostart triggers **at login**, not at the pre-login screen. For unattended recovery after a power outage, enable automatic login in **System Settings > Users & Groups** (requires FileVault to be off).

## Deploying to Another Mac

```bash
./vm deploy user@192.168.0.20 [remote-dir]
```

Syncs scripts and defaults via `rsync`, installs Tart on the remote Mac, and copies instance files that do not yet exist on the target (existing configs are preserved). On the remote Mac, run `init` and authenticate each instance. VM images and credentials stay local to each machine.

## Command Reference

| Task | Command |
|---|---|
| List all instances / inspect one | `./vm list` / `./vm -n <name> status` |
| Interactive shell / run command | `./vm shell` / `./vm run <cmd...>` |
| Copy files into / out of the guest | `./vm cp <src...> :<dst>` / `./vm cp :<src> [dst]` |
| Start / stop / restart | `./vm start` / `./vm stop` / `./vm restart` |
| Raft status, doctor, logs | `./vm raft status` / `./vm raft doctor` / `./vm raft-logs [-f]` |
| Upgrade Raft Computer | `./vm raft-upgrade` |
| Upgrade Claude Code / Antigravity CLI | `./vm claude update` / `./vm agy update` |
| Re-run guest provisioning (idempotent) | `./vm provision` |
| Upgrade Tart on the host | `./vm install-tart --force` |
| Delete VM and disk permanently | `./vm -n <name> destroy --purge` |

> `destroy` requires typing the instance name to confirm; `--purge` also removes `instances/<name>.env`.

## Repository Layout

| Path | Purpose | Committed |
|---|---|---|
| [vm](vm) | Main management script | Yes |
| [defaults.env](defaults.env) | Shared defaults for all instances | Yes |
| [instances/example.env](instances/example.env) | Instance configuration template | Yes |
| `instances/<name>.env` | Per-instance config (created by `./vm new`) | No |
| [guest/provision.sh](guest/provision.sh) | Idempotent guest provisioning script | Yes |
| [guest/raft-computer.service](guest/raft-computer.service) | Systemd user unit for Raft Computer | Yes |
| `bin/` | Local Tart binary and license | No |
| `logs/`, `.state/` | Host logs; default instance & manual-stop markers | No |

## Caveats & Known Limitations

- **Interactive Browser Auth**: OAuth / device-code flows for Raft, Claude, Antigravity, and GitHub must be approved in a browser.
- **Graceful Shutdown**: `tart stop` is a hard power-off. Always use `./vm stop`, which triggers `systemctl poweroff` inside the guest first.
- **Power Loss & Crashes**: Killing Tart abruptly or losing host power can leave recently written files zero-filled due to ext4 delayed allocation. The script defaults to `--root-disk-opts=sync=fsync` to minimize this window; set `DISK_OPTS=sync=full` for stricter durability at the cost of fsync-heavy I/O performance.
- **Memory Reclamation**: Memory allocated by a running guest is not released back to macOS until the VM shuts down.
- **Tart License**: `./vm install-tart` downloads the latest official Tart release; see `bin/TART-LICENSE` for its license terms.
