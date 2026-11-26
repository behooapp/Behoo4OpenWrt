#!/bin/sh
# Install Behoo on OpenWrt and register its signed feed for subsequent upgrades.
set -eu
umask 077
base='https://behooapp.github.io/Behoo4OpenWrt'
package=luci-app-behoo
fail() { printf '%s\n' "$*" >&2; exit 1; }
get() { wget -O "$2" "$1" || fail "下载失败：$1。请检查网络及该架构的软件源。"; }
check_hash() { printf '%s  %s\n' "$1" "$2" | sha256sum -c - >/dev/null || fail "校验失败：$2"; }

[ "$#" = 0 ] || fail '请直接运行安装脚本，无需参数。'
[ -r /etc/openwrt_release ] || fail '请在 OpenWrt 路由器的终端中运行。'
[ "$(id -u)" = 0 ] || fail '请以路由器管理员 root 身份运行。'
. /etc/openwrt_release
if [ -s /lib/apk/db/installed ] && command -v apk >/dev/null; then
    manager=apk
    command -v fw4 >/dev/null || fail '当前 APK 版本需要 firewall4。'
    flavor=apk
    # Prefer the firmware's APK package architecture to the compiled CPU name.
    arch=
    if [ -r /etc/apk/arch ]; then
        arch=$(awk 'NF { print $1; exit }' /etc/apk/arch)
    fi
    if [ -z "$arch" ]; then arch=$(apk --print-arch); fi
    key=behoo-openwrt.pem
    fingerprint='f5827b2f7dd1311c2f1c2cc2a7f4513070b7bae743bce142705a7bd8606df0e8'
    key_dest=/etc/apk/keys/$key
    config=/etc/apk/repositories.d/behoo.list
elif command -v opkg >/dev/null; then
    manager=opkg
    if command -v fw4 >/dev/null; then flavor=fw4
    elif command -v fw3 >/dev/null; then flavor=fw3
    else fail '未识别到 firewall3 或 firewall4。'; fi
    # Use the highest-priority concrete ABI understood by this opkg.
    arch=$(opkg print-architecture | awk '$1=="arch" && $2!="all" && $2!="noarch" && $3+0>n {n=$3; a=$2} END {print a}')
    key=behoo-opkg.pub
    fingerprint='ac2409d878e7392b463aaa605db4970ff9300fa3081da7330acc138f3da0305e'
    config=/etc/opkg/behoo.conf
else
    fail '无法识别此固件使用的软件包管理器。'
fi
case "$arch" in ''|*[!A-Za-z0-9_-]*) fail '无法识别 CPU 包架构。';; esac
feed="$base/feed/$flavor/$arch"
printf '系统 %s，包架构 %s，软件源 %s\n' "${DISTRIB_RELEASE:-OpenWrt}" "$arch" "$flavor"

work=$(mktemp -d /tmp/behoo-install.XXXXXX)
key_stage= config_stage=
cleanup() {
    rm -rf "$work"
    if [ -n "$key_stage" ]; then rm -f "$key_stage"; fi
    if [ -n "$config_stage" ]; then rm -f "$config_stage"; fi
}
trap cleanup EXIT
trap 'exit 1' HUP INT TERM
mkdir "$work/keys"
get "$base/keys/$key" "$work/keys/$key"
check_hash "$fingerprint" "$work/keys/$key"

if [ "$manager" = apk ]; then
    index="$feed/packages.adb"
    get "$index" "$work/packages.adb"
    apk --keys-dir "$work/keys" verify "$work/packages.adb" || fail 'APK 软件源签名无效。'
    # Resolve the download using just the verified Behoo index and release key.
    printf '%s\n' "$index" > "$work/only.list"
    apk --no-cache --keys-dir "$work/keys" --repositories-file "$work/only.list" fetch --output "$work" "$package" ||
        fail '未能从壁虎签名源下载当前架构的软件包。'
    set -- "$work"/luci-app-behoo-*.apk
    [ "$#" = 1 ] && [ -f "$1" ] || fail '未找到唯一匹配的 APK。'
    payload=$1
    apk --keys-dir "$work/keys" verify "$payload" || fail 'APK 软件包验签失败。'
    source_line="$index"
else
    command -v usign >/dev/null || fail '此固件需要 OpenWrt 的 usign 工具。'
    get "$feed/Packages.gz" "$work/Packages.gz"
    get "$feed/Packages.sig" "$work/Packages.sig"
    gzip -dc "$work/Packages.gz" > "$work/Packages"
    usign -V -p "$work/keys/$key" -m "$work/Packages" -x "$work/Packages.sig" || fail 'IPK 软件源验签失败。'
    # Each signed per-ABI index contains exactly one package record.
    field() { sed -n "s/^$1: //p" "$work/Packages"; }
    [ "$(field Package)" = "$package" ] && [ "$(field Architecture)" = "$arch" ] || fail '软件源与设备架构不匹配。'
    filename=$(field Filename)
    case "$filename" in *[!A-Za-z0-9._+-]*) fail '软件包文件名无效。';; esac
    case "$filename" in luci-app-behoo_*_"$arch".ipk) ;; *) fail '软件包文件名无效。';; esac
    payload="$work/$filename"
    get "$feed/$filename" "$payload"
    check_hash "$(field SHA256sum)" "$payload"
    get "$feed/$filename.sig" "$payload.sig"
    usign -V -p "$work/keys/$key" -m "$payload" -x "$payload.sig" || fail 'IPK 软件包验签失败。'
    key_id=$(usign -F -p "$work/keys/$key")
    case "$key_id" in ''|*[!0-9a-fA-F]*) fail 'opkg 公钥 ID 格式无效。';; esac
    key_dest=/etc/opkg/keys/$key_id
    source_line="src/gz behoo $feed"
fi

marker='# Managed by Behoo OpenWrt installer'
printf '%s\n%s\n' "$marker" "$source_line" > "$work/source"
# Never replace an unrelated administrator-managed source or key.
if [ -e "$config" ] && ! grep -qxF "$marker" "$config"; then
    fail "发现已有的软件源配置，请检查 ${config}。"
fi
if [ -e "$key_dest" ]; then check_hash "$fingerprint" "$key_dest"; fi
umask 022
mkdir -p "${config%/*}" "${key_dest%/*}"
key_stage=$(mktemp "${key_dest%/*}/.behoo.XXXXXX")
config_stage=$(mktemp "${config%/*}/.behoo.XXXXXX")
cp "$work/keys/$key" "$key_stage"
cp "$work/source" "$config_stage"
chmod 644 "$key_stage" "$config_stage"

if [ "$manager" = apk ]; then
    # Trust the standard keys for dependencies only after verifying our APK separately.
    mkdir "$work/install-keys"
    for k in /etc/apk/keys/*; do
        [ ! -f "$k" ] || cp "$k" "$work/install-keys/"
    done
    cp "$work/keys/$key" "$work/install-keys/"
    # Install by name from our staged signed repository. Local-file installs may
    # record a checksum constraint in world, preventing later normal upgrades.
    apk --no-cache --keys-dir "$work/install-keys" --repository "$work/packages.adb" add "$package"
else
    # Refresh dependency indexes only when the install needs them.
    if ! opkg --noaction install "$payload" >/dev/null 2>&1; then
        opkg update || printf '%s\n' '部分软件源刷新失败，将使用可用的索引尝试安装。' >&2
    fi
    opkg install "$payload"
fi
mv -f "$key_stage" "$key_dest"
key_stage=
mv -f "$config_stage" "$config"
config_stage=
printf '%s\n' '壁虎已安装。请打开 LuCI → 服务 → 壁虎 Behoo。' '以后可在「系统 → 软件包」刷新列表并更新壁虎。'
