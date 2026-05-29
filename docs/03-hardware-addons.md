# 03 - Thiết bị cắm thêm để tăng sức mạnh

> Authorized testing only. Xếp theo độ ưu tiên, note kernel (xem
> [01-kernel-build.md](01-kernel-build.md)) đã có driver sẵn chưa.

## Tier 1 - Must-have

| Thiết bị | Mở khóa | Kernel? |
|---|---|---|
| Alfa AWUS036ACHM (MT7610U) / AWUS036ACH (RTL8812AU) | Injection 2.4+5GHz, evil-twin, deauth | ACHM: in-tree (mt76). ACH: cần driver out-of-tree |
| TL-WN722N v1 / Panda (AR9271) | Injection 2.4GHz cực ổn, rẻ, cắm-là-chạy | `ath9k_htc` đã bật |
| USB-Ethernet adapter (AX88179 / RTL8153) | NIC thứ 2 -> Pi làm transparent bridge -> bypass 802.1X/NAC có dây | Cần thêm CONFIG (dưới) |
| RTC module DS3231 (I2C) | Giữ giờ offline. Kerberos chết nếu lệch giờ -> bắt buộc cho AD | Cần thêm CONFIG_RTC_DRV_DS1307 |
| USB LTE/4G modem (Huawei E3372...) | C2 out-of-band qua cellular, độc lập mạng target | Cần thêm WWAN driver |

NIC thứ 2 + bridge biến Pi thành vũ khí NAC bypass. RTC + cellular là 2 thứ hay
quên nhưng quyết định implant có dùng được thật hay không.

## Tier 2 - High-value

| Thiết bị | Mở khóa | Kernel? |
|---|---|---|
| Proxmark3 RDV4 / Easy | Clone thẻ ra/vào (LF 125kHz + HF 13.56MHz), MIFARE, iClass | libusb userspace |
| RTL-SDR Blog V4 | RX sub-GHz: keyfob 433MHz, ADS-B, IMSI, pager | libusb userspace |
| HackRF One | TX/RX 1MHz-6GHz: replay garage/keyfob, GPS spoof, jamming | libusb userspace |
| PoE HAT / UPS-LiPo HAT | Nguồn qua dây LAN, hoặc sống khi bị rút điện | I2C/GPIO |
| CC1101 / YARD Stick One | Sub-GHz TX/RX 300-928MHz, rfcat | YS1 userspace; CC1101 cần SPI overlay |
| nRF24L01+ / Crazyradio PA | MouseJack - bơm phím qua dongle chuột/bàn phím không dây | Crazyradio: libusb |

## Tier 3 - Chip-level / specialist

| Thiết bị | Mở khóa |
|---|---|
| CH341A + kẹp SOIC8 | Dump SPI flash -> trích firmware router/IoT/camera tìm 0-day |
| Bus Pirate / Tigard | Đa giao thức UART/SPI/I2C/JTAG/SWD |
| USB-UART (FT232/CP2102) | Console root trực tiếp router/IoT (driver đã bật) |
| MCP2515 CAN module (SPI) | CAN injection automotive/ICS (CAN_MCP251X đã bật, cần overlay) |
| Ubertooth One | Sniff Bluetooth/BLE thật (passive) |
| Sena UD100 | BT/BLE tầm xa cho BlueDucky, BLE attack |
| Logic analyzer (fx2lafw) | Đọc bus SPI/I2C/UART khi reverse hardware |
| GPS USB (u-blox) | Wardriving có tọa độ |

## Tier 4 - Hạ tầng (đừng quên)

- Powered USB 3.0 hub: Alfa + SDR + LTE ngốn điện, port Pi không gánh nổi. Bắt
  buộc khi cắm nhiều card RF.
- USB 3.0 SSD: chứa capture/loot nhanh, bền hơn SD.
- Tản nhiệt chủ động: Pi 4 throttle khi chạy hashcat/monitor liên tục.
- Case ngụy trang (ổ cắm điện, hộp PoE, power bank) cho drop-box.

## CONFIG cần thêm vào linux.fragment

```text
# USB-Ethernet (NIC thu 2 cho bridge/NAC bypass)
CONFIG_USB_NET_DRIVERS=y
CONFIG_USB_USBNET=m
CONFIG_USB_NET_AX88179_178A=m   # AX88179 gigabit
CONFIG_USB_RTL8152=m            # RTL8153 gigabit
CONFIG_USB_NET_CDCETHER=m

# USB LTE/4G modem (C2 cellular)
CONFIG_USB_SERIAL_OPTION=m
CONFIG_USB_NET_CDC_NCM=m
CONFIG_USB_NET_HUAWEI_CDC_NCM=m
CONFIG_USB_NET_QMI_WWAN=m

# RTC DS3231 (giu gio cho Kerberos)
CONFIG_RTC_DRV_DS1307=m         # cover ca DS3231

# CC1101 / nRF24 qua SPI (neu dung bien the SPI)
CONFIG_SPI_SPIDEV=y             # da bat
```

Proxmark/HackRF/RTL-SDR/YardStick/Ubertooth/Crazyradio đều userspace qua libusb
-> không cần kernel module, chỉ cần `libusb` + tool tương ứng trong rootfs.

## Loadout đề xuất (1 balo physical pentest 2026)

```
Pi4 + PoE HAT + RTC + tản nhiệt          <- core implant
2x Alfa (1 monitor, 1 rogue AP)          <- WiFi full
USB-Ethernet x1                          <- bridge / NAC bypass
USB LTE modem                            <- C2 out-of-band
Proxmark3                                <- badge cloning
HackRF + RTL-SDR                         <- RF replay/recon
CH341A + SOIC8 + USB-UART                <- hardware/firmware
Crazyradio PA                            <- mousejack
Powered USB hub + USB-SSD                <- nguon + loot
```
