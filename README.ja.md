# raft-agent-vm

[简体中文](README.md) | [English](README.en.md) | 日本語

[Tart](https://tart.run) を使い、Apple Silicon Mac 上で複数の独立した Ubuntu 仮想マシン（VM）を構築・管理するためのツールキットです。AI コーディングエージェントや開発ツールチェーンを常駐稼働させる用途に最適化されており、VM のライフサイクル管理、プロビジョニング、認証、ファイル転送を単一のスクリプト `./vm` で完結できます。

## 主な特徴

- **完全な VM 隔離**：カーネルを共有するコンテナではなく、Apple の `Virtualization.framework` 上で独立した Linux 仮想マシンを実行します。
- **SSH 不要の管理**：`tart exec` とゲストエージェント経由で操作するため、SSH 鍵や IP アドレス、パスワードの設定が不要です。
- **1 台の Mac で複数インスタンス運用**：ホスト名、ディスク、認証情報、自動起動設定が完全に分離された複数の VM を同時に運用できます。
- **すぐに使える開発環境**：冪等なプロビジョニングにより、**Raft Computer**、**Claude Code**、**Antigravity CLI**、**GitHub CLI**、**Rust**、**TiUP** を自動導入し、TiKV / `tiup playground` 向けのカーネルおよびファイルディスクリプタ上限も設定します。
- **別 Mac への簡単デプロイ**：`./vm deploy` 1 コマンドでスクリプトとインスタンス設定を別の Mac へ同期できます。

## ゲスト VM にプリインストールされる環境

`./vm init` または `./vm provision` を実行すると、以下が自動インストール・設定されます（何度実行しても安全な冪等設計）：

- **AI エージェント / オーケストレーション**：[Raft Computer](https://raft.build)（systemd ユーザーサービスとして常駐）、[Claude Code](https://claude.ai)（`claude`）、[Antigravity CLI](https://antigravity.google)（`agy`）
- **開発ツールチェーン**：GitHub CLI（`gh`）、Rust ツールチェーン（`rustup`）、TiUP（`tiup`）
- **ビルド依存パッケージ**：`build-essential`、`clang`、`cmake`、`pkg-config`、`libssl-dev`、`protobuf-compiler`、`git`、`tmux`、`jq`、`ripgrep`、`python3` など
- **システムチューニング**：`vm.max_map_count`（1,048,576）、`fs.inotify.max_user_watches`（1,048,576）、`fs.file-max`（4,194,304）、`nofile` 上限（1,048,576）を引き上げ

## 動作要件

- **ハードウェア / OS**：Apple Silicon 搭載 Mac、macOS 13 以降
- **デスクトップセッション**：自動起動を使う場合、対象ユーザーが macOS のデスクトップにログインしている必要があります
- **ネットワーク**：GitHub（Tart およびベースイメージの取得）、`cdn.raft.build`、`claude.ai`、`antigravity.google` へ接続可能であること

## クイックスタート

### 1. リポジトリの取得と環境チェック

```bash
git clone https://github.com/dulao5/raft-agent-vm.git
cd raft-agent-vm

./vm install-tart                       # Tart を ./bin にダウンロード（Homebrew・sudo 不要）
./vm doctor                             # アーキテクチャ、macOS バージョン、メモリ容量を確認
```

### 2. インスタンスの作成と初期化

```bash
./vm new dev --raft /myserver           # 'dev' インスタンスの設定を作成
./vm -n dev init                        # イメージのクローン、CPU/メモリ/ディスク設定、環境構築（初回は約 10 分）
```

> インスタンスが 1 つだけの場合、または `./vm use <name>` でデフォルトを設定済みの場合は `-n <name>` を省略できます。

### 3. 各サービスの認証と自動起動の有効化

各サービスで初回のみブラウザ承認が必要です。認証情報はゲスト VM 内に永続保存されます。

```bash
./vm -n dev raft-setup      # Raft Computer をペアリングしバックグラウンドサービスを有効化
./vm -n dev claude-login    # Claude Code にログイン
./vm -n dev agy auth        # Antigravity CLI にログイン（任意）
./vm -n dev github-login    # GitHub CLI にログインし Git 認証を設定
./vm -n dev autostart on    # macOS ログイン時の自動起動を有効化
./vm -n dev status          # VM と各サービスの状態を確認
```

## 複数インスタンスの管理

各インスタンスは `instances/<name>.env` ファイルで定義され、[defaults.env](defaults.env) の共通デフォルトを上書きします。

```bash
./vm new web --raft /myserver --cpu 4 --memory 12288 --disk 100
./vm new build --raft /myserver --memory 16384
./vm list                     # 全インスタンスの状態・リソース・自動起動を確認
./vm -n web init
./vm -n build init

./vm use web                  # デフォルトインスタンスを設定（以降 -n を省略可能）
VM=build ./vm shell           # 環境変数で一時的に指定することも可能
./vm -n all status            # 全インスタンスに対して一括実行
```

> `-n all` に対応するサブコマンド：`status`、`start`、`stop`、`restart`、`provision`、`autostart`、`raft-upgrade`。

### インスタンスごとの分離範囲

| 項目 | 分離内容 |
|---|---|
| VM とディスク | Tart VM 名はデフォルトでインスタンス名と同一。データは `~/.tart/vms/<name>` に保存 |
| ホスト名 | 新規クローン時にゲストのホスト名をインスタンス名へ自動設定 |
| Raft コンピュータ名 | インスタンスごとに独立ペアリング。Raft 上では `<Mac 名>-<インスタンス名>` として表示 |
| 認証情報 | Claude / Antigravity / GitHub の認証情報は各ゲスト内に保存され、相互に共有しない |
| 自動起動 | インスタンスごとの launchd エージェント `com.tartvm.<name>` |
| ホストログ | `logs/<name>.log` に個別出力 |

### リソース設計の目安

- **CPU**：デフォルトでホストの全論理コアを割り当てます。複数 VM が同時稼働しても安全にコアを共有します。
- **メモリ**：Linux ゲストが使用したメモリは VM 稼働中に macOS へ返却されません。**同時に起動する**インスタンスの `MEMORY_MB` 合計がホストの物理メモリを下回るように調整してください。設定済みインスタンスの合計がホストメモリの 85% を超えると、`new`・`init`・`set-mem`・`doctor` が警告を表示します。
- **同時起動台数**：Apple による同時 2 台までの制限は macOS ゲストのみが対象です。Linux ゲストにはこの制限はなく、ホストのハードウェアリソースの範囲内で運用できます。

## 各サービスの認証方法

すべての認証コマンドは対話端末を自動で接続するため SSH は不要です。認証情報はゲスト内に保存され、再起動後も維持されます。

### Raft Computer

```bash
./vm -n <name> raft-setup
```

`raft-computer setup <RAFT_SERVER> --name <RAFT_COMPUTER_NAME> --no-start` を実行し、デバイスコードと URL を表示します。ブラウザで Raft にログインして承認すると、`raft-computer` systemd ユーザーサービスが自動で有効化・起動されます。

- ペアリング解除：`./vm -n <name> raft detach <RAFT_SERVER>`

### Claude Code

- **アカウントログイン**：`./vm -n <name> claude-login` を実行し、表示された URL をブラウザで開いて承認コードを端末に貼り付けます。
- **API キー / トークン**：`./vm -n <name> claude-key` を実行し、`ANTHROPIC_API_KEY`（API 従量課金・アカウントログインより優先）または `CLAUDE_CODE_OAUTH_TOKEN`（`claude setup-token` で発行）を保存できます。認証情報はゲスト内の `~/.config/raft-vm/env`（パーミッション `600`）に保存されます。削除は `./vm -n <name> claude-key clear` です。
- **動作確認**：`./vm -n <name> claude -p "say hi"`

### Antigravity CLI（任意）

```bash
./vm -n <name> agy auth
```

対話モードの `agy` を起動します。**Google OAuth**（または **Use a Google Cloud project**）を選択し、表示された URL をブラウザで承認してコードを端末に貼り付けてください。入力プロンプトが表示されたらログイン完了です。`Ctrl+C` を 2 回押して終了すると、スクリプトが認証状態を確認し、`raft-computer` サービスを再起動します。

- ゲスト環境にデスクトップのキーチェーン（Secret Service）がないため、`~/.profile` と `raft-computer.service` の双方で `AGY_CLI_FORCE_FILE_TOKEN_STORAGE=1` を設定し、トークンをファイルとして永続化しています。
- **動作確認**：`./vm -n <name> agy -p "say hi"`
- **ログアウト**：`./vm -n <name> agy` を起動し `/logout` を実行します。

### GitHub CLI

- **ブラウザログイン**：`./vm -n <name> github-login` を実行し、Git 認証連携を承認した上で https://github.com/login/device にワンタイムコードを入力します（SAML SSO が有効な Organization がある場合は Authorize を実行してください）。
- **Personal Access Token**：`./vm -n <name> github-token` で PAT を入力してログインできます。
- 認証完了後、`git` 認証が自動構成され、未設定の場合はグローバルの `user.name` と `user.email` も自動設定されます。トークンはゲスト内の `~/.config/gh/hosts.yml` に保存されます。

## リソース変更とファイル転送

### CPU・メモリ・ディスクの変更

```bash
./vm -n dev set-disk 300     # 仮想ディスクを 300 GB に拡張（縮小不可）
./vm -n dev set-cpu 8        # CPU コア数を変更（引数省略で全コア）
./vm -n dev set-mem 28672    # メモリを変更（単位：MB）
```

- いずれのコマンドも VM を安全にシャットダウンし、設定変更後に再起動して `instances/<name>.env` を更新します。
- ディスク拡張後は次回起動時にルートパーティションが自動拡張されるため、手動での `growpart` は不要です。
- 仮想ディスクはスパースイメージのため、実際に書き込んだ容量のみを消費しますが、ゲスト内でファイルを削除しても自動で縮小されません。
- Tart のディスク容量は 10 進 GB 表記です（200 GB ≒ 186 GiB）。

### ホスト・ゲスト間のファイル転送

`./vm cp` でファイルやディレクトリを相互転送できます（ディレクトリは再帰コピー、SHA-256 で整合性を検証）：

```bash
# ホスト -> ゲスト（':' で始まるパスがゲスト側。相対パスはゲストの $HOME 基準）
./vm cp ./local.txt ./mydir :~/work/

# ゲスト -> ホスト（転送先のデフォルトはカレントディレクトリ '.'）
./vm cp :~/work/output.log .
```

## ログイン時の自動起動

```bash
./vm -n <name> autostart on    # 有効化
./vm -n <name> autostart off   # 無効化
```

launchd ユーザーエージェント（`~/Library/LaunchAgents/com.tartvm.<name>.plist`）を登録します：

- macOS へのログイン時に VM を自動起動し、ゲスト内の systemd が `raft-computer` を起動します。
- 予期せぬクラッシュ時は自動で再起動しますが、`./vm stop` で明示的に停止した場合は手動で `./vm start` するか Mac を再起動するまで停止状態を維持します。
- ログアウトやシャットダウン時には、ゲスト内で `systemctl poweroff` を実行してからプロセスを終了します。

> `Virtualization.framework` はユーザーのグラフィカルセッションを必要とするため、自動起動は**ログイン前ではなくログイン時**に行われます。停電復旧後などに無人で自動復帰させたい場合は、macOS の「システム設定 > ユーザとグループ」で自動ログインを有効にしてください（FileVault をオフにする必要があります）。

## 別の Mac へのデプロイ

```bash
./vm deploy user@192.168.0.20 [remote-dir]
```

`rsync` でスクリプトとデフォルト設定をコピーし、転送先 Mac に Tart をインストールした上で、転送先にまだ存在しないインスタンス設定ファイルを同期します（既存設定は上書きしません）。その後、転送先 Mac で各インスタンスの `init` と認証を実行してください。VM イメージと認証情報はマシンごとに独立しています。

## コマンドリファレンス

| 用途 | コマンド |
|---|---|
| 全インスタンス一覧 / 詳細ステータス | `./vm list` / `./vm -n <name> status` |
| 対話シェル / 単発コマンド実行 | `./vm shell` / `./vm run <cmd...>` |
| ゲストへのファイル送信 / 取得 | `./vm cp <src...> :<dst>` / `./vm cp :<src> [dst]` |
| 起動 / 停止 / 再起動 | `./vm start` / `./vm stop` / `./vm restart` |
| Raft 状態確認・診断・ログ | `./vm raft status` / `./vm raft doctor` / `./vm raft-logs [-f]` |
| Raft Computer のアップグレード | `./vm raft-upgrade` |
| Claude Code / Antigravity CLI の更新 | `./vm claude update` / `./vm agy update` |
| プロビジョニングの再実行（冪等） | `./vm provision` |
| ホスト側 Tart の更新 | `./vm install-tart --force` |
| VM とディスクの完全削除 | `./vm -n <name> destroy --purge` |

> `destroy` 実行時はインスタンス名の入力による確認が求められます。`--purge` を付けると `instances/<name>.env` も同時に削除されます。

## ディレクトリ構成

| パス | 役割 | Git 管理 |
|---|---|---|
| [vm](vm) | メイン管理スクリプト | あり |
| [defaults.env](defaults.env) | 全インスタンス共通のデフォルト設定 | あり |
| [instances/example.env](instances/example.env) | インスタンス設定テンプレート | あり |
| `instances/<name>.env` | 各インスタンスの設定（`./vm new` で生成） | なし |
| [guest/provision.sh](guest/provision.sh) | ゲスト内プロビジョニングスクリプト（冪等） | あり |
| [guest/raft-computer.service](guest/raft-computer.service) | Raft Computer の systemd ユーザーユニット | あり |
| `bin/` | ローカルの Tart バイナリおよびライセンス | なし |
| `logs/`、`.state/` | ホスト側ログ、デフォルトインスタンス・手動停止フラグ | なし |

## 注意事項と制限

- **ブラウザ認証**：Raft、Claude、Antigravity、GitHub の OAuth / デバイスコード認証はブラウザでの手動承認が必要です。
- **安全なシャットダウン**：`tart stop` は強制電源断となるため、VM の停止には必ず `./vm stop`（ゲスト内で `systemctl poweroff` を実行）を使用してください。
- **異常終了時のデータ保護**：Tart プロセスの強制終了や停電が発生すると、ext4 の遅延割り当てにより直近数十秒に書き込んだファイルが 0 バイトになる場合があります。デフォルトで `--root-disk-opts=sync=fsync` を有効にしてリスクを抑えています。より厳格な永続性が必要な場合は `DISK_OPTS=sync=full` を設定してください（fsync 多用時の性能は低下します）。
- **メモリ解放**：VM 稼働中に確保されたメモリは、VM をシャットダウンするまで macOS に返却されません。
- **Tart のライセンス**：`./vm install-tart` は公式の最新リリースを取得します。ライセンス条項は `bin/TART-LICENSE` を参照してください。
