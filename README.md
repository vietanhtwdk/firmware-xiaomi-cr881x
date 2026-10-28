![OpenWrt logo](include/logo.png)

# Xiaomi CR881x (CR8808 / CR8818) – OpenWrt mainline

Nhánh này thêm hỗ trợ Xiaomi CR881x vào OpenWrt main (target
`qualcommax/ipq50xx`, kernel 6.18).

> ⚠️ **Chưa được kiểm chứng trên máy thật.** Image build và kiểm tra nội dung
> đã OK, nhưng chưa boot lần nào. Nên có UART khi nạp lần đầu.

## Phần cứng

| Thành phần | Chi tiết |
|---|---|
| SoC | IPQ5018 (AP-MP03.3, machid 8040002), RAM 512 MB |
| Flash | NAND 128 MB, PEB 128 KiB, page 2048 |
| Switch | Motorcomm YT9215 (MDIO addr 0x1d, reset GPIO 39) |
| WiFi 2.4G | IPQ5018 tích hợp, BDF board-id 0x23 |
| WiFi 5G | QCN6102 (QCN6122), BDF board-id 0x60, PD 2, reset GPIO 18 |
| Nút | reset GPIO 38, mesh GPIO 28 (WPS) |
| LED | system xanh/đỏ GPIO 24/25, internet xanh/đỏ GPIO 26/27 |
| U-Boot | `bootmiwifi`, dual-boot `rootfs` (mtd18) / `rootfs_1` (mtd19), env ở `0:appsblenv` (mtd10) |

Mạng: gmac1 ──2500base-x── YT9215 port 8 (CPU). Port 0/1/2 = `lan1`/`lan2`/`lan3`,
port 3 = `wan`. Port 4 (nối GE PHY của gmac0) không dùng.

MAC lấy từ `0:art`: LAN = offset `0x06` (radio dùng +1/+2), WAN = offset `0x0c`
(giống ROM gốc dùng cho `wan_2`).

## Những gì đã thay đổi

| File | Nội dung |
|---|---|
| `target/linux/qualcommax/dts/ipq5018-cr881x.dts` | Device tree |
| `target/linux/generic/pending-6.18/761-net-dsa-add-Motorcomm-YT921x-switch-driver.patch` | Backport driver DSA `yt921x` + tag driver từ Linux 7.1 |
| `package/kernel/linux/modules/netdevices.mk` | Gói `kmod-dsa-yt921x` |
| `target/linux/generic/config-6.18` | Symbol `NET_DSA_YT921X`, `NET_DSA_TAG_YT921X` |
| `package/firmware/ipq-wifi/src/board-xiaomi_cr881x.*` | `board-2.bin` tạo từ BDF của ROM gốc (`bdwlan.b23`, `qcn6122/bdwlan.b60`) |
| `target/linux/qualcommax/image/ipq50xx.mk` | Thiết bị `xiaomi_cr881x` (FIT `config@mp03.3`, `factory.ubi` ≤ 30 MiB) |
| `target/linux/qualcommax/ipq50xx/base-files/...` | network, LED, caldata, sysupgrade, xác nhận boot sau OTA, bật flow offloading + packet steering |
| `package/boot/uboot-tools/uboot-envtools/files/qualcommax_ipq50xx` | Cấu hình `fw_env` |

Không có NSS offload: OpenWrt mainline không có driver NSS. Thay vào đó bật sẵn
software flow offloading và packet steering.

## Build (WSL / Linux)

Phải build trên filesystem phân biệt hoa thường (ví dụ `~/openwrt` trong WSL,
không phải `/mnt/d/...`). Trên WSL nên bỏ PATH của Windows, nếu không bước
`package/install` sẽ lỗi:

```sh
export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
./scripts/feeds update -a && ./scripts/feeds install -a
cat > .config <<'EOF'
CONFIG_TARGET_qualcommax=y
CONFIG_TARGET_qualcommax_ipq50xx=y
CONFIG_TARGET_qualcommax_ipq50xx_DEVICE_xiaomi_cr881x=y
CONFIG_PACKAGE_luci=y
EOF
make defconfig
make -j$(nproc)
```

Kết quả trong `bin/targets/qualcommax/ipq50xx/`:

* `*-xiaomi_cr881x-squashfs-factory.ubi` – nạp lần đầu
* `*-xiaomi_cr881x-squashfs-sysupgrade.bin` – cập nhật từ OpenWrt
* `*-xiaomi_cr881x-initramfs-uImage.itb` – boot thử qua TFTP, không ghi flash

## Nạp lần đầu (từ ROM gốc, vào `rootfs_1` / mtd19)

ROM gốc giữ nguyên ở mtd18 làm đường lui. Dùng cơ chế OTA của U-Boot Xiaomi để
nó tự quay về ROM gốc nếu bản mới không boot được:

```sh
# PC
cat openwrt-*-xiaomi_cr881x-squashfs-factory.ubi | ssh root@192.168.31.1 "cat > /tmp/factory.ubi"

# Router (ROM gốc)
ubiformat /dev/mtd19 -y -f /tmp/factory.ubi
nvram set flag_last_success=0
nvram set flag_try_sys1_failed=0
nvram set flag_try_sys2_failed=0
nvram set flag_ota_reboot=1
nvram set flag_boot_success=0
nvram commit
reboot
```

Khi boot thành công, `/etc/init.d/bootcount` đặt `flag_ota_reboot=0` và
`flag_boot_success=1`. OpenWrt lên ở `192.168.1.1`.

Cập nhật về sau: `sysupgrade` file `sysupgrade.bin`. Script ghi vào slot đang
chạy, slot còn lại không bị đụng tới.

Quay về ROM gốc từ OpenWrt:

```sh
fw_setenv flag_boot_rootfs 0
fw_setenv flag_last_success 0
reboot
```

## Việc còn lại

* Boot thử và kiểm tra: `dmesg | grep -iE "yt921x|dsa|ath11k|stmmac"`, `ip link`
* Xác nhận MAC LAN/WAN và rollback OTA của U-Boot
* NSS offload: xem hướng kernel 6.18 ở
  <https://forum.openwrt.org/t/ipq5018-nss-offload-on-kernel-6-18-with-the-upstream-ethernet-stack-gl-b3000/253014>
  (cần thêm tagger `tag_8021q` cho YT9215)

---

OpenWrt Project is a Linux operating system targeting embedded devices. Instead
of trying to create a single, static firmware, OpenWrt provides a fully
writable filesystem with package management. This frees you from the
application selection and configuration provided by the vendor and allows you
to customize the device through the use of packages to suit any application.
For developers, OpenWrt is the framework to build an application without having
to build a complete firmware around it; for users this means the ability for
full customization, to use the device in ways never envisioned.

Sunshine!

## Download

Built firmware images are available for many architectures and come with a
package selection to be used as WiFi home router. To quickly find a factory
image usable to migrate from a vendor stock firmware to OpenWrt, try the
*Firmware Selector*.

* [OpenWrt Firmware Selector](https://firmware-selector.openwrt.org/)

If your device is supported, please follow the **Info** link to see install
instructions or consult the support resources listed below.

##

An advanced user may require additional or specific package. (Toolchain, SDK, ...) For everything else than simple firmware download, try the wiki download page:

* [OpenWrt Wiki Download](https://openwrt.org/downloads)

## Development

To build your own firmware you need a GNU/Linux, BSD or macOS system (case
sensitive filesystem required). Cygwin is unsupported because of the lack of a
case sensitive file system.

### Requirements

You need the following tools to compile OpenWrt, the package names vary between
distributions. A complete list with distribution specific packages is found in
the [Build System Setup](https://openwrt.org/docs/guide-developer/build-system/install-buildsystem)
documentation.

```
binutils bzip2 diff find flex gawk gcc-6+ getopt grep install libc-dev libz-dev
make4.1+ perl python3.8+ rsync subversion unzip which
```

### Quickstart

1. Run `./scripts/feeds update -a` to obtain all the latest package definitions
   defined in feeds.conf / feeds.conf.default

2. Run `./scripts/feeds install -a` to install symlinks for all obtained
   packages into package/feeds/

3. Run `make menuconfig` to select your preferred configuration for the
   toolchain, target system & firmware packages.

4. Run `make` to build your firmware. This will download all sources, build the
   cross-compile toolchain and then cross-compile the GNU/Linux kernel & all chosen
   applications for your target system.

### Related Repositories

The main repository uses multiple sub-repositories to manage packages of
different categories. All packages are installed via the OpenWrt package
manager called `opkg`. If you're looking to develop the web interface or port
packages to OpenWrt, please find the fitting repository below.

* [LuCI Web Interface](https://github.com/openwrt/luci): Modern and modular
  interface to control the device via a web browser.

* [OpenWrt Packages](https://github.com/openwrt/packages): Community repository
  of ported packages.

* [OpenWrt Routing](https://github.com/openwrt/routing): Packages specifically
  focused on (mesh) routing.

* [OpenWrt Video](https://github.com/openwrt/video): Packages specifically
  focused on display servers and clients (Xorg and Wayland).

## Support Information

For a list of supported devices see the [OpenWrt Hardware Database](https://openwrt.org/supported_devices)

### Documentation

* [Quick Start Guide](https://openwrt.org/docs/guide-quick-start/start)
* [User Guide](https://openwrt.org/docs/guide-user/start)
* [Developer Documentation](https://openwrt.org/docs/guide-developer/start)
* [Technical Reference](https://openwrt.org/docs/techref/start)

### Support Community

* [Forum](https://forum.openwrt.org): For usage, projects, discussions and hardware advise.
* [Support Chat](https://webchat.oftc.net/#openwrt): Channel `#openwrt` on **oftc.net**.

### Developer Community

* [Bug Reports](https://bugs.openwrt.org): Report bugs in OpenWrt
* [Dev Mailing List](https://lists.openwrt.org/mailman/listinfo/openwrt-devel): Send patches
* [Dev Chat](https://webchat.oftc.net/#openwrt-devel): Channel `#openwrt-devel` on **oftc.net**.

## License

OpenWrt is licensed under GPL-2.0
