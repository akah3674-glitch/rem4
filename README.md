# 🐉 Hồi Ức Ngọc Rồng – Termux Auto Setup

Script tự động cài đặt private server **Hồi Ức Ngọc Rồng (HUNR)** trên Android Termux.

## 🚀 Cài đặt nhanh

```bash
curl -fsSL https://raw.githubusercontent.com/akah3674-glitch/rem4/main/hunr_setup.sh | bash
```

## 📦 Nguồn game (Google Drive)

| File | Drive ID | Nội dung |
|------|----------|---------|
| `HUNR_Server.zip` | `1qQDKBYGRUxZma7Ax_8z1_v_s54_jAU09` | Server Spring Boot + resources (~1.1GB) |
| `HUNR_Client.zip` | `11W9nK8XA1209D1nzi2D7tGzxpM5X9a4t` | Unity source code client |
| `Barcoll [HUNR].rar` | `1UD_thIvP54w08ticP9LL6-Xi1EZKT24A` | Mod Local |

## ⚙️ Thông tin server

| Mục | Giá trị |
|-----|---------|
| Game port | `14445` (TCP) |
| Admin/HTTP port | `1707` |
| Database | `hunr_2026` (MariaDB/MySQL) |
| JAR | `HunrProvision-0.0.1-SNAPSHOT.jar` |
| Server list | `https://hoiucnro.com/server.txt` |

## 📋 Cấu trúc sau khi cài

```
~/hunr-server/
├── HunrProvision-0.0.1-SNAPSHOT.jar   # Server chính (Spring Boot)
├── application.properties              # Config (DB, ports, game settings)
├── Config/
│   └── config.ini                      # Config tỉ lệ, sao, exp...
├── resources/                          # Assets game (ảnh, data, map)
├── sql/
│   └── bo_mong_setup.sql              # SQL phụ (bổ mộng)
├── logs/
│   └── server.log                      # Log server
├── start.sh                           # Khởi động
└── stop.sh                            # Dừng
```

## 🎮 Menu script

```
1. Setup lần đầu (tải + cài đặt hoàn toàn)
2. Khởi động server
3. Dừng server
4. Xem log server
5. Vào MySQL shell
6. Thông tin server
0. Thoát
```

## 📱 APK Client

Client ZIP chứa Unity source code (không có APK build sẵn).  
APK có thể lấy từ **Barcoll [HUNR].rar** (Mod Local).

Kết nối local: server list cấu hình `Local:127.0.0.1:14445:0`

## ⚡ Requirements Termux

```bash
pkg install openjdk-17 mariadb unzip curl wget
```

RAM khuyến nghị: ≥ 2GB free  
Storage: ≥ 3GB (ZIP 1.1GB + extracted)

## ⚠️ Lưu ý

- `spring.jpa.hibernate.ddl-auto=update` → server **tự tạo bảng** khi khởi động lần đầu
- Nếu DB còn trống, server sẽ tạo schema tự động
- Backup DB bằng `mysqldump -u root hunr_2026 > backup.sql`
