# 壁虎 Behoo for OpenWrt

## 简介

壁虎 Behoo 是一款 OpenWrt 路由器代理插件。你可以在路由器管理界面（LuCI）导入订阅、选择线路、指定哪些局域网设备使用代理，并查看当前连接和实时流量。

- 官网：[https://behoo.us/openwrt](https://behoo.us/openwrt)
- 邮箱：`behooapp [at] gmail`

当前版本为 **luci-app-behoo 0.1.3**，入口在「服务 → 壁虎 Behoo」。管理服务由 procd 启动，代理使用包内的 Mihomo v1.19.33。初次安装时代理关闭，所有设备默认直连。

## 官网一键安装与更新

部署后使用 [壁虎 OpenWrt 安装页](https://behoo.us/openwrt/)。用户以 root 登录路由器终端，复制页面中的一行命令。安装程序根据包管理器、CPU 架构和实际防火墙选择软件源，校验固定公钥指纹、仓库签名和安装包，再安装插件。使用 SSH 或固件已有的网页终端均可。

APK 软件源写在 `/etc/apk/repositories.d/behoo.list`，opkg 软件源写在 `/etc/opkg/behoo.conf`，两者均保留固件现有的软件源。后续在 LuCI「系统 → 软件包」刷新列表即可更新壁虎。移除上述对应的源文件即可取消订阅该源。

### 发布到 behoo.us

GitHub Actions 的 **Build OpenWrt packages** 会额外产出 `behoo-openwrt-website`。解压后把**目录内的内容**部署到网站的 `/openwrt/`，同一目录应同时提供 `index.html`、`install.sh`、`keys/` 和 `feed/`。普通 HTTPS 静态站点、Nginx 或对象存储均可。GitHub Release 仍用于插件「关于」页的版本提示。

发布新版时先上传新版本包文件，再发布签名索引、脚本和页面。保留旧版本包一段时间，供仍缓存旧索引的路由器下载。对安装脚本、首页及 `packages.adb`、`Packages.gz`、`Packages.sig` 使用短缓存或重新验证；支持原子部署的主机可一次切换整份站点。静态目录只应包含发布产物和公钥。

## 选择安装包

在路由器 SSH 终端查看固件版本和包架构。运行 `apk --print-arch` 或 `opkg print-architecture`，下载与输出完全匹配的 ZIP。在电脑上解压，按下表选择其中一个安装包。

| 官方固件系列 | 对应文件 | 防火墙和界面 |
| --- | --- | --- |
| 25.12 | `apk/*.apk` | APK v3 内置 RSA 签名，fw4 / nftables，LuCI JS |
| 24.10、23.05、22.03 | `fw4/*.ipk` | opkg，fw4 / nftables，LuCI JS |
| 21.02、19.07、18.06 | `fw3/*.ipk` | opkg，fw3 / iptables，Lua LuCI 菜单 |

定制固件请以实际组件为准。`command -v fw4` 和 `command -v fw3` 可查看防火墙版本。两个 IPK 的包名相同，放在不同目录。

| 包架构 | ZIP 内的版本 |
| --- | --- |
| `x86_64`、`aarch64_generic`、`aarch64_cortex-a53`、`aarch64_cortex-a72` | APK、fw4 IPK、fw3 IPK |
| `arm_cortex-a7_neon-vfpv4`、`arm_cortex-a9_vfpv3-d16`、`arm_cortex-a15_neon-vfpv4` | APK、fw4 IPK、fw3 IPK |
| `mips_24kc`（大端）、`mipsel_24kc`（小端） | APK、fw4 IPK、fw3 IPK |
| `aarch64_cortex-a76` | APK、fw4 IPK |
| `arm_cortex-a9_vfpv3` | fw3 IPK |

插件自带 Mihomo。根据架构，文件展开后约 46–53 MiB，安装包约 17–19 MiB。运行 `df -h /overlay /tmp` 检查写入空间和上传临时空间，并为规则库、订阅和依赖预留余量。部分旧路由器需要 extroot 扩容才能安装。版本表表示适配目标，本版尚未在各代路由器上逐一安装验证。

### OpenWrt 25.12

将 ZIP 里的 `keys/behoo-openwrt.pem` 和对应的 APK 复制到路由器 `/tmp/`。首次安装先核对发布公钥文件的 SHA-256，再加入 apk 的信任目录。

```sh
echo 'f5827b2f7dd1311c2f1c2cc2a7f4513070b7bae743bce142705a7bd8606df0e8  /tmp/behoo-openwrt.pem' | sha256sum -c - &&
  mkdir -p /etc/apk/keys &&
  cp /tmp/behoo-openwrt.pem /etc/apk/keys/behoo-openwrt.pem &&
  apk add "/tmp/luci-app-behoo-0.1.3-r1_$(apk --print-arch).apk"
```

也可以先完成公钥校验与复制，再到 LuCI「系统 → 软件包 → 上传软件包」上传解压得到的 `.apk`。遇到 `/tmp/upload.apk: v2 package format error` 时，重新选择 `apk/` 目录下的文件；IPK 和 ZIP 都不能作为 APK 上传。

### OpenWrt 24.10 及更早的 opkg 系列

将所选目录里的一对 `.ipk` 和 `.ipk.sig`，以及 `keys/behoo-opkg.pub` 复制到路由器 `/tmp/`。下面的命令以 x86_64 为例，按实际文件名修改第一行。通过 SSH 安装可以对本地 IPK 单独验签。

```sh
pkg=/tmp/luci-app-behoo_0.1.3-1_x86_64.ipk
echo 'ac2409d878e7392b463aaa605db4970ff9300fa3081da7330acc138f3da0305e  /tmp/behoo-opkg.pub' | sha256sum -c - &&
  usign -V -p /tmp/behoo-opkg.pub -m "$pkg" -x "$pkg.sig" &&
  opkg install "$pkg"
```

如果提示缺少依赖，确认当前固件的软件源可用，运行 `opkg update` 后再次执行验签和安装。维护软件源时，分别发布 fw3 和 fw4 目录中的 IPK、`Packages.gz` 和 `Packages.sig`。在路由器上核对公钥指纹后执行 `opkg-key add /tmp/behoo-opkg.pub`，即可使用 opkg 对软件源索引验签。

安装后重新登录 LuCI，打开「服务 → 壁虎 Behoo」。在「关于」中可查看已安装版本、编译日期、项目链接及致谢，点击「检查更新」可查询 BehooWRT 的最新正式 GitHub Release 标签。可用 `ubus list -v behoo` 查看管理接口，或用 `logread -e behoo` 检查服务。卸载命令分别为 `apk del luci-app-behoo` 和 `opkg remove luci-app-behoo`。普通升级、重启及卸载保留 `/etc/behoo` 中的设置和订阅。

## 首次使用

1. 在「我的订阅」中填入壁虎 JSON v1 或 Clash YAML 订阅地址。导入完成前会显示处理状态，校验失败时可修改地址重试。
2. 进入「线路配置」，依次选择订阅、规则或全局模式、自动或手动出口、需要代理的局域网设备，再点「应用配置」。规则模式的「全自动驾驶」保留订阅原有规则顺序和 MATCH 默认策略。订阅没有规则时自动选线；「手动驾驶」可替换订阅的默认代理出口。
3. 在「连接概览」点「连接代理」。以后可在「局域网设备」更改选择并点「应用策略」。
4. 「连接概览」显示当前出口和上下行速率。「当前连接」可按目标、来源设备、命中规则或出口搜索。若要在客户端手动设置代理，在「设置」中将接管方式改为「HTTP / SOCKS5」，地址为路由器的 LAN IPv4，端口为 `17990`。

透明模式处理主逻辑接口 `lan` 上所选 MAC 的公网 IPv4 TCP 流量，以及这些设备发往路由器 LAN IPv4 的标准 DNS 请求。局域网、路由器管理流量、其他 UDP、IPv6 和访客网络沿用原路由。切换策略后，应新建连接验证。设备列表读取主 LAN 的 ARP 邻居和默认 DHCP 租约文件 `/tmp/dhcp.leases`，也支持手工添加 MAC。

## 构建与签名

在仓库根目录运行。需要 Python 3.9+、Go 1.26.x、OpenSSL 和 OpenWrt 的 usign。可用 `BEHOO_GO` 指定 Go 工具链。两个环境变量 `BEHOO_APK_KEY` 和 `BEHOO_OPKG_KEY` 分别指向与仓库公钥匹配的发布私钥文件。

```sh
out=dist/openwrt/0.1.3
python3 openwrt/build-ipk.py
python3 openwrt/build-ipk.py --legacy
python3 openwrt/sign-ipks.py --sign-key "$BEHOO_OPKG_KEY" "$out/fw3" "$out/fw4"
python3 openwrt/build-apk.py --index-dir "$out/indices" --sign-key "$BEHOO_APK_KEY" --output "$out/apk" "$out"/fw4/*.ipk
python3 openwrt/bundle.py "$out"
python3 openwrt/build-site.py "$out" --indices "$out/indices" --opkg-key "$BEHOO_OPKG_KEY" --output "$out/web/openwrt"
```

`build-ipk.py` 接受一个或多个包架构名，例如 `python3 openwrt/build-ipk.py --legacy mipsel_24kc`。管理服务和 Mihomo 按 CPU 静态编译，MIPS 使用软件浮点。ZIP 在 `dist/openwrt/0.1.3/downloads/`。

GitHub Actions 的 **Build OpenWrt packages** 需要配置 `BEHOO_APK_SIGNING_KEY` 和 `BEHOO_OPKG_SIGNING_KEY` 两个 Secrets（私钥文件全文）。工作流使用带 SHA-256 校验的 25.12.6 SDK，对发布的 APK 逐个运行原生 `apk verify` 和解包检查，并使用 SDK 的 `usign` 签发并验证 IPK 及软件源索引。私钥只用于签名步骤。固件版本、包管理和防火墙切换见 [OpenWrt APK 文档](https://openwrt.org/docs/guide-user/additional-software/apk) 与 [OpenWrt 22.03 版本说明](https://openwrt.org/releases/22.03/start)。
