<h1 align="center">luci-app-honk</h1>

<p align="center">OpenWrt x86_64 / aarch64 / armv7 上的 <b>Honk</b> 透明代理一体包：<b>honk</b> 核心 + <b>Doona</b> 面板 + <b>LuCI</b> 运维界面。</p>

<p align="center">English summary: a packaging and operations layer for Honk on OpenWrt. It ships the eBPF proxy core, the Doona web panel and a LuCI page set that keeps only the sysadmin duties. All configuration editing lives in Doona, which talks to the core's native API.</p>

---

## 这个仓库负责什么

Honk 这套东西由三个独立项目组成，本仓库只承担其中的**打包层与运维层**：

| 项目 | 角色 | 本仓库的用法 |
|---|---|---|
| [honk](https://github.com/daeuniverse/honk) | eBPF 透明代理内核 | 从源码交叉编译成 musl 静态二进制，打进 `honk` 包 |
| [Doona](https://github.com/Zakkaus/doona) | 原生 API 的 Web 面板 | 从源码构建成静态资源，随 `honk` 包装到 `/usr/share/doona`，由内核在 `/ui/` 托管 |
| **本仓库** | 打包 + 运维 | OpenWrt 包定义、procd 服务、LuCI 运维界面、发布流水线 |

**配置管理不在本仓库。** 节点、订阅、分组、路由规则、DNS 的增删改全部由 Doona 通过内核的原生 API 完成。本仓库不提供第二套配置写入路径。

**面板随 `honk` 包走，不随 `luci-app-honk` 走。** 内核启动时要从 `/usr/share/doona`
读面板的 `index.html`，目录不存在就拒绝启动。面板资产如果放在依赖 `honk` 的
`luci-app-honk` 里，单独装 `honk`、或卸载 LuCI 包之后，服务就起不来。所以面板资产
直接进 `honk` 包，`luci-app-honk` 只剩 LuCI 页面与 rpcd 脚本（架构无关，仍是
noarch）。代价是每个架构的包多带约 1.3 MB 的面板资源。

### LuCI 界面保留什么

| 页面 | 职责 |
|---|---|
| 概览 | 服务启停、核心与面板版本、内核版本、系统状态、**打开 Doona** 入口、首次初始化 |
| 日志 | 核心日志按级别与行数过滤 |
| 维护 | Geo 数据更新、软件包升级、配置备份与恢复、系统检查与修复、重置 |
| 设置 | 监听端口、LAN 网络、开机自启 |

设置页原先还有一个"配置"页面，可以直接添加订阅、粘贴节点、导入 `.dae` 文件。该页面连同 500 行的订阅转换器一起**已移除**：它用文本改写 `config.dae`，与内核自身的校验、事务和回滚机制并行，容易造成两边状态不一致。改由 Doona 统一处理后，配置只有一个写者。

---

## 安装

```bash
wget -O - https://raw.githubusercontent.com/szwjp/luci-app-honk/refs/heads/main/scripts/install.sh | ash
```

大陆网络加速（可选）：

```bash
export GH_PROXY=https://ghfast.top
wget -O - https://raw.githubusercontent.com/szwjp/luci-app-honk/refs/heads/main/scripts/install.sh | ash
```

`GH_PROXY` 只给 release 资产的下载加一层前缀，脚本本身仍然从 GitHub 直取。`SHA256SUMS`
文件的 sha256 摘要从 `api.github.com`（不走代理）读取并校验，代理即使替换了校验文件或公钥
也会被拒；校验通过后，公钥再装入 `/etc/apk/keys` 并由 apk 校验安装包的签名。

卸载：

```bash
wget -O - https://raw.githubusercontent.com/szwjp/luci-app-honk/refs/heads/main/scripts/uninstall.sh | ash
```

安装后进入 LuCI「服务 → Honk」，先做首次初始化与系统检查，再启动服务。初始化会创建 Doona 的管理员账号（用户名与密码），之后在 Doona 里管理节点与规则。

一键脚本会复用设备已有的 Geo 数据包；缺少时从聚合源下载，下载失败则尝试设备现有软件源。

脚本的下载链是完整的：它只挑**正式版** release（跳过 `source-*` / `candidate-*`
预发布），先用 GitHub API 记录的 `SHA256SUMS` 摘要锚定校验文件，再逐个安装包比对
`SHA256SUMS`，把同一 release 发布的签名公钥装进 `/etc/apk/keys/`，最后用普通
`apk add` 安装——签名对不上就装不进去。第三方代理只是可选的传输层加速：它能影响
可用性，但无法替换校验文件、公钥或安装包。

Doona 面板资源随 `honk` 包发布。升级时请同时升级 `honk` 与 `luci-app-honk`；在 LuCI
维护页升级 `luci-app-honk` 会先升级 `honk`，避免旧 `honk` 的依赖文件被新 LuCI 包删掉。

委派权限时分两级：只读用户授予 `luci-app-honk-read`（概览与日志）；需要维护、更新、
备份恢复等操作的管理员同时授予 `luci-app-honk-read` 与 `luci-app-honk-admin`。维护页
只对 admin 角色可见。

---

## 端口与安全边界

原生 API 默认监听 `0.0.0.0:9527`，也就是设备上的所有接口。**这是本仓库与上游默认行为不同的地方**，边界因此从"套接字绑定"移到了"防火墙规则"：

```
config rule 'honk_native_api_lan'    src=lan  dest_port=9527  target=ACCEPT
config rule 'honk_native_api_wan'    src=wan  dest_port=9527  target=REJECT
```

如果设备上还有其它 firewall zone（guest、iot 等），脚本会为每个 zone 生成一条
`honk_native_api_reject_<zone>` 的 REJECT 规则；`src=lan` 会按 `honk.main.lan_network`
实际所属的 zone 生成，而不是固定写死 `lan`。

这两条规则由 `honk` 包在安装、初始化、改端口和系统修复时写入 `/etc/config/firewall`，卸载时移除。

选通配地址而不是写死局域网 IP，是因为路由器改 IP 后，写死的绑定会让面板静默失联。改用通配后，路由器换地址不影响面板。

> 如果你更看重"套接字根本不监听 WAN"这一层，而不在意换 IP 的场景，把 `/etc/honk/system.dae` 里的 `listen: '0.0.0.0:9527'` 改成具体局域网 IP 即可，例如 `listen: '192.168.1.1:9527'`。此时 Doona 只能用这个地址访问，路由器换 IP 后需要重新初始化或系统修复。

### `lan_interface` 列表语法

`global.lan_interface` 是列表。官方 honk 解析器当前推荐**裸逗号分隔**（每项不加引号）：

```
lan_interface: br-lan, ipsec0, tun0
```

逐项加引号（`'br-lan', 'ipsec0'`）仍能解析，但会触发 `legacy-list-quoting` 警告；整段加引号是更旧的写法。本包的初始化/改端口/备份/修复会保留设备上已有的完整列表，不会把它压回单个 `br-lan`。

内核侧还有两道与本仓库无关的防线：管理员密码用 PBKDF2-HMAC-SHA256（10 万轮）散列，会话是不透明随机令牌，内存里只留 SHA-256 摘要，12 小时过期且重启即失效。

**注意**：用域名访问 Doona 时，内核在通配绑定下只接受 IP 字面量或 `localhost` 作为 Host，需要域名访问时在 `native_api` 里配 `allowed_hosts` 与 `allow_origins`，然后重启内核。

管理入口和 API 只应在可信 LAN 内使用。若 LuCI 通过未加密的 HTTP 提供，浏览器到路由器之间的登录信息和 API 流量没有传输加密保护；请勿将管理页面暴露到互联网。

---

## 权限模型

LuCI 页面背后的 rpc 方法分成两个角色，ACL 文件分别是
`/usr/share/rpcd/acl.d/luci-app-honk-read.json` 与 `luci-app-honk-admin.json`：

| 角色 | 能做什么 |
|---|---|
| `luci-app-honk-read` | 概览、日志、状态检查等只读操作 |
| `luci-app-honk-admin` | 全部操作：初始化、启停、改设置、修复、备份/恢复/重置、Geo 数据源写入、软件包升级 |

「只看」和「动手」被拆开之后，只读账号拿不到任何 root 权限的执行入口。
Geo 数据源以前走通用的 uci 写接口，等于把整个 `honk` 配置段的写权限都交了出去；
现在换成专用的 `honk.set_geo` 方法，只能写那四个 Geo 字段。

---

## 面板缺失时的降级

面板资源缺失**不会**让服务起不来。内核的 `ui:` 指向 `/usr/share/doona`，
而 `honk` 包里同时带了一份兜底页面 `/usr/share/honk/ui`：面板资源不在时，
`system.dae` 里写的是兜底路径，内核照常启动，只是 `/ui/` 显示一张
「面板资源缺失，请重新安装 honk 包」的说明页。

LuCI 的概览页会明确提示这一点，不会让你对着一个打不开的面板猜原因。
重新安装 `honk` 包即可恢复完整面板。

## 固定源码与构建

核心和 Doona 的完整提交、Doona 的 OpenWrt 补丁摘要、apk-tools 与 `po2lmo` 的地址和 SHA256 全部固定在 `ci/pins.env`。

> **上游状态**：`honk` 的原生 API 已于 2026-10-20 通过 PR #299 合入官方 [`daeuniverse/honk`](https://github.com/daeuniverse/honk) 的 `main`，本仓库直接锁定官方上游，不再依赖任何 fork 分支。核心按 `main` 分支头跟踪，并以该提交自己的上游 CI 全绿作为采纳条件。

Doona 从源码构建，保留 OpenWrt 同源适配补丁；归档不含可选中文字体，浏览器使用系统字体。构建脚本从固定输入生成静态 UI、stock musl 核心和安装包。

### 无人值守：每日一次的上游检查

`auto-bump.yml` 每天北京时间早上 08:00（UTC 00:00）自动跑一次，检查两个上游是否有新内容：

| 上游 | 检查对象 | 说明 |
|---|---|---|
| [Zakkaus/doona](https://github.com/Zakkaus/doona) | 最新的 release（含预发布） | 面板版本；release tag 不可变，tag 相同即无新发布 |
| [daeuniverse/honk](https://github.com/daeuniverse/honk) | `main` 分支头上**上游 CI 全绿**的提交 | 官方上游；原生 API 自 2026-10-20 起已在 `main` 中 |

两个上游的判定方式不同：

- **Doona** 用 release tag。tag 不可变，tag 相同就说明没有新发布。
- **Honk 核心**用提交。上游的 dated debug tag 需要人工推送，发布频率远低于 `main` 分支本身的变动频率，按 tag 检查会让包落后很多。分支头本身没有"这个提交已发布"的保证，因此**以该提交自己的上游 CI 判定**：只有必过的 12 条检查通道（workspace/aarch64 测试、eBPF 真实内核 VM 测试、musl 发布路径、fmt+clippy 等）全部 `success` 的提交才会被采纳。任一条仍在运行、失败或缺失，就回退到上一个全绿的提交。通道清单写在 `ci/pins.env` 的 `UPSTREAM_REQUIRED_LANES`，上游改通道名时只改那一处，不必动工作流。

  判定严格区分两种情况：**通道没通过**和 **GitHub API 调不动**。API 出错时这一轮直接失败并报错，不会把它当成"这条通道没通过"然后悄悄退回到更旧的提交；回退窗口最多 20 个提交，整个窗口全红时同样报错退出，而不是随便挑一个旧提交去构建。

上游的每日提交集中在 UTC 12:00–22:00 之间，把检查安排在 UTC 00:00，一轮即可收齐当天的全部改动，而不是拿一个当天稍晚就会被推翻的中间态；离次日活动开始也还留有两小时余量。

提交没变时检查脚本直接结束，**不建分支、不提交、不触发构建**，整轮静默。

一旦发现新提交，流水线会：

1. 把 `ci/pins.env` 的 `CORE_COMMIT` / `CORE_RELEASE` 更新到该提交，把 `DOONA_COMMIT` / `DOONA_RELEASE` 更新到新的 Doona release；
2. 在独立分支上写入 pin、包版本与 Doona 归档哈希；
3. 启动 `release.yml` 构建核心、Doona 和全部 6 个架构的安装包（单 job，无矩阵）。任一步失败就停止晋级；
4. 全部通过后，才把验证过的提交和正式 tag 原子推送到 `main`，发布正式 Release，并更新软件源。

包的构建来源是**上游 CI 已判定为全绿的那个提交**：既有分支头的时效，又有上游测试兜底，且每个提交上游都会跑完整的通道集合。

手动触发同一条流水线：

```sh
gh workflow run auto-bump.yml
```

完整构建需要在大小写敏感的 Linux 文件系统上运行（Doona 上游同时有仅大小写不同的文件）。需要 Rust/rustup、Zig 0.14.1、Node.js 22.13 或更新版本与 Corepack、Git、curl、ripgrep、GNU tar、zstd、`readelf`、openssl 与 C 编译器，以及 `build-essential`、clang、LLVM、libbpf、libelf、pkg-config、CMake、libclang。核心交叉编译脚本会核对 Rust/Doona 输入和 Zig、bpf-linker 版本；打包阶段限定 Linux x86_64。

在满足工具要求的 Linux 环境中按顺序运行：

```sh
bash scripts/check.sh
ci/build-doona.sh
ci/build-core.sh
```

脚本将源码归档写入被 Git 忽略的 `artifacts/cache/`。

安装包由 `release.yml` 用 **apk-tools 直接构建，不经过 OpenWrt SDK**：两个包的 `Build/Compile` 都是空的，核心二进制由 `ci/build-core.sh` 单独交叉编译，LuCI 侧只有文件拷贝和一次 `po2lmo`。SDK 在这里除了打包、签名、生成 `/lib/apk/packages/*` 元数据和建索引之外没有别的用途，而 `apk mkpkg` / `apk mkndx` 本身就能做这四件事。

因此各架构的差别只是"往包里放哪个预编译二进制"，矩阵从 12 个 job 塌成 1 个 job 内部循环 6 个架构。apk-tools 取 Alpine 的 `apk-tools-static`（约 2 MB，校验 SHA256），`po2lmo` 从 pin 住的 luci 提交现场编译（lemon 生成 `plural_formula.c`）。

安装阶段需要仓库 secret `APK_PRIVATE_KEY`，否则构建直接失败并给出生成命令。

工作流里的第三方 action 全部固定到 commit SHA（不用会漂移的 tag），
`scripts/check.sh` 会断言这一点：谁改了一个 `@v7` 之类的浮动引用，检查直接失败。

---

## 依赖

| 包名 | 说明 |
|------|------|
| `ca-bundle` | CA 证书包，用于校验订阅与 Geo 数据的 HTTPS 下载 |
| `kmod-sched-core` / `kmod-sched-bpf` | eBPF 流量调度 |
| `kmod-veth` | 虚拟以太网设备 |
| `kmod-nft-queue` | nftables 队列 |
| `v2ray-geoip` / `v2ray-geosite` | 路由 GeoIP/GeoSite 数据 |
| `rpcd` / `luci-base` / `cgi-io` | LuCI 运行依赖 |

内核需要 BTF（`/sys/kernel/btf/vmlinux`），honk-core 用 CO-RE eBPF，缺少 BTF 会启动失败。

内核还需要 **function tracer**（`CONFIG_FUNCTION_TRACER`）：UDP 接收路径是用 fentry
挂在内核函数上的，没有它 eBPF 挂不上，honk 就只代理 TCP，UDP 与 QUIC 流量直接漏过去。
官方 ImmortalWrt 的内核默认没有开这个选项，所以：

- LuCI 的概览页与「系统检查」会给出 `udp_trace_unavailable` 警告（不影响服务启动）；
- `available_tracers` 里只有 `nop` 时就是这个状态。

要代理 UDP/QUIC，需要自己编译带 `CONFIG_FUNCTION_TRACER=y` 的内核；只跑 TCP 的话
现有内核就够。判断方法：

```sh
cat /sys/kernel/tracing/available_tracers 2>/dev/null \
  || cat /sys/kernel/debug/tracing/available_tracers
```

输出里有 `function` 就是支持的，只有 `nop` 就是不支持。

## 系统要求

OpenWrt 24.10 及更早版本使用 Linux 6.6，低于 honk 要求的 6.12。**推荐 OpenWrt 25.12 或更新版本**（内核 Linux 6.12+ 且开启 BTF）。

---

## 已知限制

- **开机时核心会等到上行就绪才启动。** honk 的 WAN 接口配成 `auto`，上游按「最低 metric 的 IPv4 默认路由」解析它，而 PPPoE 拨号完成前没有这条路由。核心若在那之前启动，会绑上 LAN hook 却没有 WAN hook：节点健康检查全败，UDP 与多叶节点出站处于 fail-closed 状态。因此开机序列里的启动在 WAN 就绪前会被推迟（日志里记 "the WAN is not ready yet"），由 `/etc/hotplug.d/iface/99-honk` 在上行到位后把核心拉起。面板、设置与升级路径发起的启动不受这个限制，它们本来就在等核心就绪。
- **不能在 macOS 上构建。** Doona 源码含仅大小写不同的文件，构建脚本会主动探测并拒绝在大小写不敏感的文件系统上继续。
- **OpenWrt SDK 已完全移除。** 改用 apk-tools 直接出包，不再下载 272 MB 的 SDK、不再构建约 1 GB 的 `immortalwrt/sdk` 镜像，矩阵从 12 个 job 变成 1 个。代价是包元数据的生成逻辑由本仓库自己维护（对照 `include/package-pack.mk` 抄写），`scripts/check.sh` 会断言 Makefile 里每个安装目标都在 `ci/build-apk.sh` 里被 stage，防止两边漂移。
- **只支持 25.12 及以上。** 24.10 的 opkg/`.ipk` 通道已停止——apk-tools 3 产不出 ipk，保持两套打包语义不划算。
- **安装层已在真机验证（ImmortalWrt 25.12.1 / x86_64）。** `.apk` 实装通过：依赖解析、`/etc/uci-defaults/90-honk` 执行、防火墙规则落地、LuCI / rpcd / Doona 文件就位，卸载时规则与文件也清理干净。aarch64 / armv7 架构与真实代理流量仍未验证。
- **签名更新源需要外部引导。** 内核的受签名更新通道读取 `/etc/honk/update-trust/feed.url`，该文件由仓库外的流程写入，仓库内没有写入者。
- **实机验证只覆盖安装层。** 结构检查（`scripts/check.sh`）覆盖语法与静态一致性；真机验证了安装、卸载与静态文件，代理转发、eBPF、DNS 等运行时行为仍需单独验证。
- **打包与运行时冒烟测试在 PR 上跑。** 拉取请求会跑两个冒烟 job：用一次性签名密钥走一遍和 release 完全相同的打包流程（`ci/build-apk.sh` + `apk adbdump` 断言 + 文件布局断言），以及用 `honk-core --mock-ebpf` 起一个实例，跑一遍面板用到的原生 API 与 CLI（`ci/smoke-native-api.sh`）。打包缺陷不用等到发版才暴露。
- **面板资源在每个架构包里各带一份。** 面板必须和内核同包（内核启动时就要读它），所以 6 个架构包各多约 1.3 MB。

---

## 仓库设置

发布流水线需要**一个必配 secret** 加一组可选变量。

**Secrets**：

| 名称 | 用途 |
|---|---|
| `APK_PRIVATE_KEY` | 打包签名私钥（EC prime256v1 PEM）。缺失时 `build` job 直接失败并打印生成命令。对应的公钥随每次 Release 发布，供设备信任。 |

```sh
mkdir -p ~/.config/honk
openssl ecparam -name prime256v1 -genkey -noout -out ~/.config/honk/apk-key.pem
chmod 600 ~/.config/honk/apk-key.pem
bash scripts/set-apk-key.sh
```

**Variables**（非敏感，仓库设置页可改）：

| 名称 | 默认 | 用途 |
|---|---|---|
| `AGGREGATE_FEED_REPOSITORY` | 空 | 聚合 feed 的目标仓库；为空则不触发聚合 |

### 软件源即 GitHub Releases

`scripts/install.sh` 从 GitHub Releases API 读取安装包，不依赖任何对象存储，
`upload_feed` job 是叶子节点——没人 `needs` 它。因此下面的 Cloudflare R2
凭据**当前不配置，这是预期状态**：

| 名称 | 用途 |
|---|---|
| `R2_ACCESS_KEY_ID` | R2 访问密钥 ID |
| `R2_SECRET_ACCESS_KEY` | R2 访问密钥 |
| `R2_ENDPOINT` | `https://<account>.r2.cloudflarestorage.com` |
| `R2_BUCKET` | 存放软件源的 bucket |

四个值缺任意一个，`upload_feed` job 就在第一步打印 warning 并结束，
不下载 artifacts、不装 rclone；流水线仍为绿色。

若以后要启用，凭据从仓库外的文件读入，值不进参数列表也不进 shell 历史：

```sh
mkdir -p ~/.config/honk
cat > ~/.config/honk/r2-secrets <<'EOF'
R2_ACCESS_KEY_ID=...
R2_SECRET_ACCESS_KEY=...
R2_ENDPOINT=https://<account>.r2.cloudflarestorage.com
R2_BUCKET=...
EOF
chmod 600 ~/.config/honk/r2-secrets
bash scripts/set-r2-secrets.sh
```

### 受签名的更新通道尚未启用

设备端 `honk/files/update.sh` 要求设备上存在 `/etc/honk/update-trust/feed.url`
与 `manifest.pub`，并校验 usign 签名的 `manifest.json`。仓库内目前既没有写入
`feed.url` 的步骤，也没有签名步骤（发布端只生成未签名的
`release-manifest.json`）。设备端的行为是诚实失败：返回
`trusted_feed_unavailable`，不会装未验证的包。启用前需要先补上签名链路。

**当前的更新通道只能检查、不能应用。** 即使签名链路补齐，设备端还缺一份
"可回滚的完整包集合"：更新要能退回去，就得同时能装回旧版本，否则中途失败只会把
设备留在半更新状态。`update_apply` 因此固定返回 `rollback_tuple_unavailable`，
LuCI 的「软件包升级」按钮只会做检查，不会真的换包。换包请用安装脚本重新装一遍。

### 软件源的目录结构

R2 上的 feed 按 OpenWrt 版本和架构分目录，目录名取自 `ci/pins.env` 的
`OPENWRT_RELEASE`：

```
openwrt-feed/honk/25.12/<arch>/honk-<version>-<arch>.apk
openwrt-feed/honk/25.12/<arch>/luci-app-honk-<version>-noarch.apk
openwrt-feed/honk/25.12/<arch>/packages.adb      # 只索引本架构的包
openwrt-feed/honk/luci-app-honk.pub.pem         # 签名公钥
```

每个架构目录里的 `packages.adb` 只列本架构的包（外加架构无关的 `luci-app-honk`），
不是全架构的索引；公钥跟索引放在一起，客户端才建得起信任。

---

## 致谢

- [honk](https://github.com/daeuniverse/honk) — eBPF 透明代理核心
- [Doona](https://github.com/Zakkaus/doona) — 核心的 Web 面板
- [doona 文档](https://zakkaus.github.io/doona-docs/zh-CN/) — 原生 API 字段参考与 OpenWrt 部署指引

本仓库基于 [kenzok8/openwrt-honk](https://github.com/kenzok8/openwrt-honk) 重构而来，保留了其 OpenWrt 打包与发布链路。

## 许可证

本仓库原创集成文件采用 GPL-3.0-only。Honk 核心与 Doona 各自保留上游许可和第三方声明；打包时随软件安装至 `/usr/share/licenses/`。核心提交、Doona 提交、补丁摘要及实际阶段归档散列记录在构建生成的 provenance 文件中。
