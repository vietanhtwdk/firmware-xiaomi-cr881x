# Xiaomi CR881x – firmware RA82 quốc tế

*[English](README.en.md)*

Bộ script build firmware **Xiaomi Mesh System AX3000 (RA82) bản quốc tế**
cho **Xiaomi CR881x** (CR8808 / CR8818, bản nhà mạng CMCC): giao diện Xiaomi,
mesh, app Mi WiFi / Xiaomi Home quốc tế, NSS offload.

* Phần mềm (web, mesh, app) lấy từ file firmware RA82 **chính hãng**.
* Phần cứng (kernel, module, firmware WiFi/NSS, công cụ switch YT9215) lấy từ
  **bản dump ROM gốc CR8818** (mtd18) của máy cần cài.
* SSH (cổng 22) dùng mật khẩu root đặt lúc build, UART giữ nguyên.

Đã chạy thực tế trên CR8818: boot, switch, WiFi 2.4/5 GHz, trang cài đặt web.

Repo chỉ chứa script và patch. Không có firmware Xiaomi hay dữ liệu của máy
(bản quyền Xiaomi; dump chứa SN, MAC, mật khẩu xuất xưởng).

## build.sh làm gì

| Bước | Nội dung |
|---|---|
| Kernel | Volume `kernel` của ROM gốc CR8818 (FIT có cấu hình `mp03.3`) |
| Module | `/lib/modules` của ROM gốc (khớp kernel) |
| Firmware | `IPQ5018/WIFI_FW`, `qcn6122`, `qca-nss0*.bin`, `read_caldata_to_fs.sh` của ROM gốc |
| Switch | `switch_ctl` của ROM gốc, autoload `yt-9215s`, `qca-ssdk-nohnat`, `qca-nss-dp` |
| Bỏ | LVM, cấu hình mã hóa LUKS (`89_mount_sec_cfg`): cần module `loop`/`dm-crypt` mà kernel CR8818 không có |
| Ảnh router | Thêm `router_ra82_101*.png` cho biến thể màu `101` |
| Patch | Xem bảng dưới |
| nvram | Preinit `33_cr881x_nvram`, chạy mỗi lần boot |
| root | Mật khẩu từ `ROOT_PASSWORD`, `/etc/shadow` quyền 600 |
| ZeroTier | Tùy chọn, nếu có `ZEROTIER_BIN` |
| Dropbear | Tùy chọn, nếu có `DROPBEAR_BIN` |

| Patch | Nội dung |
|---|---|
| `10-switch-yt9215-ports.patch` | Cổng RA82 (LAN 1-3, WAN 4, CPU 5/6) → YT9215 (LAN 0-2, WAN 3, CPU 4/5) |
| `20-leds.patch` | Tên LED theo device tree CR881x (`sys_blue`/`sys_red`) |
| `30-international.patch` | Kiểm tra mạng/NTP không dùng máy chủ Trung Quốc, trang đăng nhập tiếng Anh |
| `40-disable-upgrade.patch` | Tắt OTA và nút nâng cấp web: firmware RA82 chính hãng **không có driver YT9215**, nạp vào sẽ mất mạng dây |
| `50-boot-ssh.patch` | Tắt PHY tới khi boot xong, không đặt lại mật khẩu root, luôn bật SSH |
| `60-dropbear-hostkeys.patch` | Host key SSH lưu ở `/data/dropbear`, giữ qua reboot; `-R` tự sinh key còn thiếu (ed25519 với dropbear mới) |

### nvram của máy CMCC

nvram dùng chung với ROM gốc CR8818 và bị `bdata sync` ghi đè khi reset, nên
lệch với những gì firmware RA82 chờ. `33_cr881x_nvram` sửa lại mỗi lần boot:

| nvram | Triệu chứng nếu thiếu | Sửa |
|---|---|---|
| `EncryptMode` | Đăng nhập web luôn `401 not auth` (server so SHA1 với mã băm SHA256) | `1` |
| `CountryCode` | Chạy vùng `CN` | `COUNTRY` lúc build, chỉ khi trống hoặc `CN` |
| `wl1_ssid`/`wl0_ssid` | Tên `CMCC-xxxx` làm trang cài đặt lỗi `formatSsidName` | `Xiaomi_XXXX`, chỉ khi là `CMCC-*` |

## Build

Cần Linux/WSL với `python3 squashfs-tools mtd-utils fakeroot openssl patch`.

Lấy dump ROM gốc trên router đang chạy ROM gốc ở mtd18:

```sh
dd if=/dev/mtd18 of=/tmp/mtd18.bin
```

Build (mã quốc gia phải có trong `/etc/config/country_mapping` của RA82):

```sh
COUNTRY=VN ROOT_PASSWORD='...' ./build.sh \
    miwifi_ra82_firmware_db06e_1.4.31_INT.bin \
    mtd18.bin \
    out
```

Kết quả: `out/cr881x-ra82-1.4.31-mod.ubi` (~27 MB, tối đa 30 MB) và `.sha256`.

### Chọn tính năng (FEATURES)

`FEATURES` chọn phần tùy chọn đưa vào image (mặc định `adblock wol`):

| Feature | Thêm gì | Cần |
|---|---|---|
| `adblock` | `/usr/sbin/adblock-update` (DNS blocklist) | — |
| `wol` | `/usr/bin/wol` (Wake-on-LAN) | — |
| `zerotier` | ZeroTier + dịch vụ tự chạy | `ZEROTIER_BIN=` |
| `dropbear` | thay dropbear mới (ed25519) | `DROPBEAR_BIN=` |
| `sshfallback` | dropbear cũ ở cổng 2222 (SSH cứu hộ) | — |

Các bản sửa phần cứng (đánh số cổng YT9215, LED, nvram, host key SSH, tắt
nâng cấp) **luôn có**, không nằm trong `FEATURES`.

```sh
FEATURES="adblock wol zerotier dropbear" \
    ZEROTIER_BIN=out/zerotier-one DROPBEAR_BIN=out/dropbear \
    COUNTRY=VN ROOT_PASSWORD='...' ./build.sh <ra82.bin> <mtd18.bin> out

FEATURES= ... ./build.sh ...     # không thêm gì
```

## Nạp

CR881x có hai slot: `rootfs` (mtd18) và `rootfs_1` (mtd19). Chỉ ghi được vào
slot **đang không chạy**. Xem slot đang chạy:

```sh
cat /proc/cmdline | grep -o "ubi.mtd=[a-z_0-9]*"
```

Chép image lên router bằng `scp -O` (dropbear không có SFTP). **Không dùng
`cat file | ssh ...` trong PowerShell**: `cat` là `Get-Content`, đọc file như
văn bản và làm hỏng file nhị phân.

```sh
scp -O out/cr881x-ra82-1.4.31-mod.ubi root@192.168.31.1:/tmp/mod.ubi
```

Router chạy dropbear cũ (chỉ có `ssh-rsa`) thì thêm `-o HostKeyAlgorithms=+ssh-rsa`.
Luôn kiểm tra `sha256sum /tmp/mod.ubi` khớp file `.sha256` trước khi `ubiformat`.

Đang chạy từ mtd18 (`ubi.mtd=rootfs`), ghi vào mtd19:

```sh
ubiformat /dev/mtd19 -y -f /tmp/mod.ubi
nvram set flag_try_sys2_failed=0
nvram set flag_boot_rootfs=1
nvram set flag_last_success=1
nvram set flag_format_overlay=1
nvram commit
reboot
```

Đang chạy từ mtd19 (`ubi.mtd=rootfs_1`), ghi vào mtd18 (ghi đè ROM gốc, cần
giữ bản dump để khôi phục):

```sh
ubiformat /dev/mtd18 -y -f /tmp/mod.ubi
nvram set flag_try_sys1_failed=0
nvram set flag_boot_rootfs=0
nvram set flag_last_success=0
nvram set flag_format_overlay=1
nvram commit
reboot
```

* U-Boot chọn slot theo `flag_boot_rootfs` và `flag_last_success`; hai cờ phải
  cùng giá trị. **Không có rollback tự động**: nếu bản mới không boot, cần UART.
  `flag_ota_reboot` không làm U-Boot đổi slot.
* `flag_format_overlay=1`: hai slot dùng chung phân vùng cấu hình `overlay`
  (mtd20, mount ở `/data`). `/etc/passwd`, `/etc/shadow`, `/etc/config`... chỉ
  được chép từ ROM vào `/data` khi `/data` vừa format. **Bắt buộc** khi chuyển
  từ ROM gốc CMCC hoặc từ bất kỳ firmware nào khác. Chỉ bỏ cờ
  này khi cập nhật từ chính bản build của repo này, để giữ cấu hình.
* Cờ format được ROM boot kế tiếp dùng: nếu U-Boot vẫn boot slot cũ thì slot
  cũ bị format cấu hình.
* Lần SSH đầu tiên sau khi nạp sẽ báo host key thay đổi: `ssh-keygen -R 192.168.31.1`.

Quay về ROM gốc (khi ROM gốc còn ở mtd18):

```sh
nvram set flag_boot_rootfs=0
nvram set flag_last_success=0
nvram commit
reboot
```

## ZeroTier

Kernel CR8818 có sẵn TUN, chỉ cần binary. Firmware dùng musl cũ của OpenWrt
18.06 nên build `zerotier-one` dạng static:

```sh
sudo apt install g++-arm-linux-gnueabihf
tools/build-zerotier.sh 1.14.2 out
ZEROTIER_BIN=out/zerotier-one COUNTRY=VN ROOT_PASSWORD='...' ./build.sh <ra82.bin> <mtd18.bin> out
```

Identity và mạng đã join lưu ở `/data/zerotier`: giữ qua reboot, mất khi format
`/data` hoặc reset (khi đó router có node ID mới, phải duyệt lại).

### Setup ZeroTier

1. Tạo mạng trên [ZeroTier Central](https://my.zerotier.com), ghi lại
   **Network ID** (16 ký tự hex). Ví dụ dưới dùng dải ZeroTier `10.147.17.0/24`
   và LAN của router `192.168.31.0/24`.

2. Trên router (SSH), kiểm tra dịch vụ và join mạng:

   ```sh
   zerotier-cli info                    # 200 info <node id> 1.14.2 ONLINE
   zerotier-cli join <network id>
   ```

   Nếu báo không kết nối được: `/etc/init.d/zerotier restart`, chờ vài giây.

3. Trên ZeroTier Central, mục **Members**: tick **Auth** cho node ID của router
   và đặt cho nó một IP cố định, ví dụ `10.147.17.1`.

4. Kiểm tra trên router:

   ```sh
   zerotier-cli listnetworks            # trạng thái OK, interface ztXXXXXXXX, IP
   ip addr show | grep -A2 " zt"
   ```

5. Mở firewall cho interface ZeroTier. Firewall Xiaomi dựng lại luật mỗi lần
   reload, nên luật phải nằm trong một script `include`:

   ```sh
   cat > /data/zerotier/firewall.sh <<'EOF'
   #!/bin/sh
   # Truy cập router và LAN từ mạng ZeroTier
   for rule in "INPUT -i zt+" "FORWARD -i zt+" "FORWARD -o zt+"; do
       iptables -C $rule -j ACCEPT 2>/dev/null || iptables -I $rule -j ACCEPT
   done
   EOF
   chmod +x /data/zerotier/firewall.sh

   uci set firewall.zerotier=include
   uci set firewall.zerotier.path=/data/zerotier/firewall.sh
   uci commit firewall
   /data/zerotier/firewall.sh
   ```

   Chỉ cần truy cập chính router (web, SSH) thì giữ dòng `INPUT`, bỏ hai dòng
   `FORWARD`.

6. Truy cập các máy trong LAN (tùy chọn): trên ZeroTier Central, mục
   **Managed Routes**, thêm `192.168.31.0/24` via `10.147.17.1` (IP ZeroTier của
   router). Máy khác trong mạng ZeroTier khi đó tới được `192.168.31.x`.

   Nếu không muốn thêm route, có thể NAT thay vào đó (máy LAN sẽ thấy kết nối
   đến từ IP của router), thêm vào `firewall.sh`:

   ```sh
   iptables -t nat -C POSTROUTING -s 10.147.17.0/24 -o br-lan -j MASQUERADE 2>/dev/null ||
       iptables -t nat -I POSTROUTING -s 10.147.17.0/24 -o br-lan -j MASQUERADE
   ```

7. Thử từ một máy khác trong mạng ZeroTier: `ping 10.147.17.1`, mở
   `http://10.147.17.1`, rồi `ping 192.168.31.x` nếu đã làm bước 6.

Rời mạng: `zerotier-cli leave <network id>`. Tắt hẳn (`/etc/rc.d` chỉ đọc nên
không dùng được `disable`): `touch /data/zerotier/disabled; /etc/init.d/zerotier stop`.
Bật lại: `rm /data/zerotier/disabled; /etc/init.d/zerotier start`.

Image build trước khi có `/var/lib/zerotier-one` → `/data/zerotier`: chạy
`ln -sfn /data/zerotier /var/lib/zerotier-one` (mất khi reboot) hoặc dùng
`zerotier-cli -D/data/zerotier ...`.

Luật firewall ở bước 5–6 chưa được thử trên máy thật; nếu không vào được, kiểm
tra `iptables -S | grep zt` và `ip route`.

## SSH

Dropbear 2017.75 của firmware chỉ có host key `ssh-rsa`; OpenSSH ≥ 8.8 từ chối:
`no matching host key type found. Their offer: ssh-rsa`. Thay bằng dropbear
mới (có `ed25519`, `rsa-sha2-256`), build static với musl. Có hai cách, đều
đã chạy thực tế trên router:

```sh
# Nhanh (vài phút): gcc ARM của Ubuntu + musl build từ mã nguồn
sudo apt install gcc-arm-linux-gnueabihf
tools/build-dropbear.sh 2026.94 out

# Hoặc dùng toolchain musl có sẵn, ví dụ OpenWrt target ipq40xx
# (Cortex-A7, chạy được trên Cortex-A53 của IPQ5018 ở chế độ 32-bit):
#   trong cây OpenWrt: make tools/install toolchain/install
tools/build-dropbear.sh --toolchain \
    <openwrt>/staging_dir/toolchain-arm_cortex-a7+neon-vfpv4_gcc-*_musl_eabi \
    2026.94 out

DROPBEAR_BIN=out/dropbear ZEROTIER_BIN=out/zerotier-one COUNTRY=VN ROOT_PASSWORD='...' ./build.sh <ra82.bin> <mtd18.bin> out
```

Thay `2026.94` bằng đường dẫn tarball `dropbear-*.tar.bz2` để khỏi tải; tương
tự `MUSL=<phiên bản|tarball>` cho musl (mặc định 1.2.6).

Dropbear trong image là binary đa năng: `dropbear`, `ssh`/`dbclient`, `scp`,
`dropbearkey` đều trỏ tới `/usr/sbin/dropbear`. Đã chạy thực tế (v2026.94).

Không thay dropbear thì thêm vào `~/.ssh/config` của máy client:

```
Host 192.168.31.1
    HostKeyAlgorithms +ssh-rsa
    PubkeyAcceptedAlgorithms +ssh-rsa
```

Host key lưu ở `/data/dropbear` (bind-mount lên `/etc/dropbear`,
`60-dropbear-hostkeys.patch`) nên không đổi sau reboot; chỉ đổi khi format
`/data` hoặc reset.

### SSH cứu hộ (không có UART)

Nếu dùng dropbear mới, nên thêm `sshfallback`: dropbear **cũ** (2017.75) chạy
song song ở cổng **2222**, độc lập với dropbear chính ở cổng 22. Lỡ dropbear
mới không lên sau khi nạp, vẫn vào được để sửa mà không cần UART:

```sh
ssh -o HostKeyAlgorithms=+ssh-rsa -p 2222 root@192.168.31.1
```

Telnet trên firmware này không chạy (busybox telnetd thoát 255), nên đây là
lưới an toàn thay thế, và vẫn mã hóa. Khi chắc dropbear chính ổn, có thể tắt:
`/etc/init.d/dropbear-fallback disable; /etc/init.d/dropbear-fallback stop`.

## Adblock (DNS sinkhole)

Firmware đã có `dnsmasq`; chặn quảng cáo ở tầng DNS như Pi-hole mà không cần
cài thêm gì nặng. Script `/usr/sbin/adblock-update` (có sẵn trong image) tải
blocklist dạng hosts và sinh `/data/dnsmasq.d/adblock.conf`
(`address=/domain/#`, chặn cả tên miền con).

Cài một lần trên router:

```sh
uci set dhcp.@dnsmasq[0].confdir=/data/dnsmasq.d
uci commit dhcp
adblock-update
```

`adblock-update` tự tải (có timeout), chuyển định dạng, rồi restart dnsmasq.
Danh sách nguồn ở `/data/adblock.lists` (một URL mỗi dòng; mặc định StevenBlack
~77k tên miền). Ở Việt Nam `raw.githubusercontent.com` hay chậm/treo — đổi sang
CDN jsDelivr cho nhanh:

```sh
echo 'https://cdn.jsdelivr.net/gh/StevenBlack/hosts@master/hosts' > /data/adblock.lists
```

Cập nhật định kỳ bằng cron:

```sh
echo '0 5 * * 0 /usr/sbin/adblock-update >/tmp/adblock.log 2>&1' >> /etc/crontabs/root
/etc/init.d/cron enable; /etc/init.d/cron restart
```

Tắt: `uci delete dhcp.@dnsmasq[0].confdir; uci commit dhcp; /etc/init.d/dnsmasq restart`.
Mọi thứ nằm trong `/data`, mất khi format `/data` hoặc reset (chạy lại các bước).

Sinh file trên PC rồi `scp -O` vào `/data/dnsmasq.d/` cũng được:
`tools/adblock-gen.sh out/adblock.conf`.

## Sửa file trên router không cần nạp lại

Rootfs là squashfs chỉ đọc. Có thể bind-mount bản sửa đặt trong `/data` đè lên
file gốc, chạy lại mỗi lần boot qua `include` của firewall (`/etc/config` nằm
trong `/data`):

```sh
uci set firewall.my_patch=include
uci set firewall.my_patch.path=/data/patch/apply.sh
uci commit firewall
```

`apply.sh` phải kiểm tra trước khi mount, vì firewall reload sẽ chạy lại nó.

## Công cụ

* `tools/xiaomi_fw.py hdr1 <miwifi_*.bin> <out.ubi>`: tách image UBI từ file firmware Xiaomi
* `tools/xiaomi_fw.py ubi <ubi|mtd dump> <dir>`: tách các volume UBI
* `tools/adblock-gen.sh [out.conf] [url ...]`: sinh dnsmasq blocklist từ danh sách hosts
* `tools/build-zerotier.sh`, `tools/build-dropbear.sh`: build binary static ARMv7
