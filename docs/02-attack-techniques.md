# 02 - Kỹ thuật tấn công triển khai từ Pi 4 implant (2026)

> Authorized testing only. Map từng tính năng kernel/phần cứng (xem
> [01-kernel-build.md](01-kernel-build.md)) sang kỹ thuật còn ăn trong 2026, kèm
> note reality để không xài đồ lỗi thời.

## 1. WiFi / Wireless (monitor + injection)

| Kỹ thuật | Tool | Reality 2026 |
|---|---|---|
| PMKID / handshake capture -> crack | hcxdumptool, hashcat | Vẫn ăn ngon trên WPA2-PSK. Chủ lực. |
| Evil Twin + EAP cred harvest | eaphammer, hostapd-mana | Cướp domain creds qua WPA-Enterprise nếu client không validate cert. |
| Rogue AP / KARMA / MANA | hostapd-mana, wifiphisher | Bắt thiết bị tự kết nối, captive portal phishing. |
| Deauth / disassoc | aireplay, mdk4 | Chết với WPA3/PMF (802.11w). Còn ăn WPA2 không bật PMF. |
| WPA3 downgrade / transition-mode | Dragonblood | Transition mode ép tụt về WPA2. |
| WPS Pixie Dust | reaver, bully | Chỉ router cũ. |
| Probe-request tracking / de-anon | kismet, bettercap | Theo dõi thiết bị qua MAC/SSID đã lưu. |
| Wardriving / mapping | kismet + GPS USB | Recon thụ động diện rộng. |

6GHz (WiFi 6E/7) cần adapter mới; chip onboard chỉ 2.4/5GHz.

## 2. USB Gadget - cắm vào máy nạn nhân

Điểm mạnh nhất của setup vì kernel có `dwc2 + libcomposite`.

- BadUSB / HID injection: Pi giả bàn phím, gõ stager (PowerShell/bash) tốc độ máy.
  Không cần driver -> bypass nhiều chính sách USB mass-storage.
- USB-Ethernet gadget (RNDIS/ECM) -> credential theft: Pi giả NIC, thành default
  gateway/DNS -> chạy Responder ngay trên Pi, hốt NetNTLMv2 hash kể cả khi máy
  khóa màn hình (QuickCreds/PoisonTap).
- Composite HID + Ethernet: HID gõ lệnh kéo payload từ chính NIC ảo của Pi.
- Serial/ACM gadget: kênh C2 ngầm qua USB.

Reality 2026: PoisonTap/QuickCreds bị Windows mới hạn chế network lúc lock (tùy
bản/policy); org trưởng thành có device-control. Tỉ lệ trúng vẫn cao ở endpoint
thường. EDR có thể bắt timing HID -> chèn jitter.

## 3. Drop-box trên LAN (cắm dây vào mạng target)

Kho lớn nhất khi Pi có chỗ đứng trong LAN:

- Poisoning -> relay: LLMNR/NBT-NS/mDNS poison (Responder) -> bắt NetNTLMv2 ->
  ntlmrelayx relay sang LDAP/SMB -> ADCS ESC8 relay, dump SAM.
- mitm6 (IPv6 takeover): rogue DHCPv6 + WPAD -> MITM toàn LAN. Cực mạnh 2026 vì
  IPv6 thường không ai quản.
- Coercion: PetitPotam, PrinterBug/SpoolSample, Coercer -> ép DC auth về -> relay.
- AD recon/attack: netexec (nxc), BloodHound collector, Kerberoasting,
  AS-REP roasting, Certipy (ADCS).
- 802.1X / NAC bypass (wired): Pi làm transparent bridge núp sau thiết bị đã xác
  thực (silentbridge / nac_bypass). Cần NIC thứ 2 (USB-Ethernet).
- Pivot/tunnel về operator: ligolo-ng / chisel / WireGuard -> chạy metasploit,
  burp từ máy bạn xuyên qua Pi.

Reality 2026: LLMNR/NBT-NS hay bị tắt mặc định -> mDNS + mitm6 thành chủ lực.
NTLM đang bị khai tử dần, SMB signing enforce nhiều hơn -> ưu tiên Kerberos relay
và ADCS.

## 4. Bluetooth / BLE

- BLE recon/GATT enum -> tấn công smart lock, IoT, thiết bị y tế.
- BlueDucky / CVE-2023-45866 (BlueZ HID injection): bơm keystroke qua Bluetooth
  vào Android/Linux chưa patch - còn nhiều thiết bị dính 2026.
- BLE spam / advertising flood: gây nhiễu, popup pairing -> DoS / social-eng.
- Beacon spoof/clone; KNOB/BLUR (legacy).

## 5. Hardware hacking (UART/SPI/I2C/JTAG/CAN)

- UART console -> root shell trực tiếp router/IoT/camera (GND/TX/RX).
- SPI flash dump (flashrom + kẹp SOIC8) -> trích firmware để phân tích/0-day.
- JTAG (OpenOCD) -> debug, dump, bypass secure boot yếu.
- CAN bus injection (MCP2515 đã enable): candump/cansend, replay -> automotive/ICS.
- I2C/SPI EEPROM dump cấu hình/secret.

## 6. Mở rộng qua USB add-on

- RTL-SDR / HackRF: bắt-phát sub-GHz (keyfob 433/315MHz, garage), ADS-B, IMSI
  catcher GSM, GPS spoof.
- PN532 (I2C/SPI/UART): clone thẻ RFID/NFC, tấn công MIFARE Classic.
- Adapter WiFi thứ 2: 1 con monitor + 1 con rogue AP đồng thời.

## 7. C2 / Exfil / Persistence

- Reverse C2 bền qua WireGuard, fallback autossh.
- Exfil ngầm: DNS tunneling (iodine/dnscat2), ICMP, covert channel khi firewall chặn.
- Beaconing cron; read-only rootfs + overlayfs -> anti-forensics.

## Kill-chain mẫu (physical pentest, drop-box)

```
1. Lẻn vào, cắm Pi vào ổ LAN trong phòng họp (dây) + cấp nguồn PoE
2. Boot -> WireGuard call-home về VPS operator
3. Pi tự: mitm6 + Responder -> bắt NetNTLMv2
4. ntlmrelayx -> ADCS ESC8 -> lấy cert -> Kerberos TGT (Certipy)
5. netexec spray domain -> tìm host có local admin
6. ligolo-ng: operator ngồi nhà chạy BloodHound/secretsdump xuyên qua Pi
7. Đồng thời WiFi card phụ: evil-twin hốt thêm WPA-Ent creds
8. Exfil loot qua WireGuard, Pi giữ persistence read-only
```
