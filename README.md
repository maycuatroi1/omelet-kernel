# omelet-kernel

Biến Raspberry Pi 4 thành một headless stealth pentest implant: build hệ điều
hành + Linux kernel tùy biến hoàn toàn từ source bằng Buildroot.

> Chỉ dùng cho pentest/red-team có ủy quyền (owner-approved). Authorized testing only.

## Mục tiêu thiết kế

- Nền tảng: **Buildroot from-scratch** (kernel + rootfs cùng một chỗ, reproducible).
- Form factor: **headless stealth implant** (drop-box), điều khiển từ xa qua C2.
- Khả năng: **all-purpose** lớp CLI trên Pi, đồ nặng (metasploit/burp) chạy trên
  máy operator và pivot xuyên qua Pi.
- Mục tiêu chính: tùy biến sâu tới mức **tự build Linux kernel** với patch/driver
  phục vụ tấn công (USB gadget, WiFi injection, BLE, hardware buses, tunneling).

## Phần cứng cơ bản

- Raspberry Pi 4 (khuyến nghị 4GB/8GB), build image 64-bit (aarch64).
- WiFi onboard BCM43455c0: monitor mode + injection qua nexmon.
- Cổng USB-C: USB OTG/gadget mode (dwc2) cho tấn công HID/BadUSB.
- 4x USB-A: cắm adapter WiFi ngoài, SDR, LTE modem...
- Bluetooth + GPIO (UART/SPI/I2C/CAN) cho hardware hacking.

## Tài liệu

| File | Nội dung |
|------|----------|
| [docs/01-kernel-build.md](docs/01-kernel-build.md) | Pipeline Buildroot + custom kernel, config fragment, nexmon, driver, tooling, implant, build & flash |
| [docs/02-attack-techniques.md](docs/02-attack-techniques.md) | Kho kỹ thuật tấn công triển khai được (2026), kill-chain mẫu |
| [docs/03-hardware-addons.md](docs/03-hardware-addons.md) | Thiết bị cắm thêm để tăng sức mạnh, theo tier, kèm CONFIG cần bổ sung |
| [docs/linux.fragment](docs/linux.fragment) | Kernel config fragment dùng trực tiếp với Buildroot |

## Quick start

```bash
git clone https://git.buildroot.net/buildroot
cd buildroot && git checkout 2024.02.x
make raspberrypi4_64_defconfig
# tro fragment: BR2_LINUX_KERNEL_CONFIG_FRAGMENT_FILES="board/pi4-implant/linux.fragment"
make -j$(nproc)
sudo dd if=output/images/sdcard.img of=/dev/sdX bs=4M conv=fsync status=progress
```

Chi tiết xem [docs/01-kernel-build.md](docs/01-kernel-build.md).
