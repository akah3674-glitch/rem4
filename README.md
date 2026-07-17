# 🐉 Hồi Ức Ngọc Rồng – Termux Auto Setup v2.0

Script tự động cài đặt và chạy offline **Hồi Ức Ngọc Rồng (HUNR)** trên Android Termux.

## 🚀 Cài đặt nhanh

```bash
curl -fsSL https://raw.githubusercontent.com/akah3674-glitch/rem4/main/hunr_setup.sh | bash
```

---

## 🔌 Chạy offline – Cách hoạt động

```
[APK] → HTTP GET http://127.0.0.1:1707/lists.txt
                         ↓
              [Spring Boot server trả về]
              Local:127.0.0.1:14445:0,0,0
                         ↓
         [Game kết nối TCP → 127.0.0.1:14445]
                         ↓
              [HUNR Spring Boot game server]
```

**Tại sao cần patch APK?**  
APK gốc lấy danh sách server từ `https://hoiucnro.com/server.txt` (server thật online).  
Sau khi patch, APK lấy từ `http://127.0.0.1:1707/lists.txt` (server local trên Termux).  
Code game đã có sẵn `str = localIP` → tự động kết nối `127.0.0.1:14445`. ✅

---

## 📋 Các bước sử dụng

### Bước 1 – Setup server (chỉ làm 1 lần)
```
Menu 1: Setup lần đầu
```
Script tự tải HUNR_Server.zip (~1.1GB), giải nén, cấu hình MariaDB, tạo `start.sh`.

### Bước 2 – Patch APK (chỉ làm 1 lần)
```
Menu 7: Patch APK → chạy offline
```
- Cần APK gốc của HUNR (tải từ hoiucnro.com hoặc cài sẵn)
- Script sẽ tự tìm APK trong thư mục Downloads
- Patch binary `global-metadata.dat`: đổi URL server list
- Ký APK bằng debug keystore
- Xuất ra `~/hunr-server/HUNR-offline.apk`

### Bước 3 – Cài APK patched
```bash
cp ~/hunr-server/HUNR-offline.apk /sdcard/Download/
# Mở File Manager → cài APK
```

### Bước 4 – Khởi động và chơi
```
Menu 2: Khởi động server
→ Mở game HUNR → chọn server "Local" → chơi!
```

---

## 📦 Nguồn file game

| File | Drive ID | Nội dung |
|------|----------|---------|
| `HUNR_Server.zip` | `1qQDKBYGRUxZma7Ax_8z1_v_s54_jAU09` | Server Spring Boot + resources (~1.1GB) |
| `HUNR_Client.zip` | `11W9nK8XA1209D1nzi2D7tGzxpM5X9a4t` | Unity source code (Windows build) |
| `Barcoll [HUNR].rar` | `1UD_thIvP54w08ticP9LL6-Xi1EZKT24A` | Windows PC client (test local trên PC) |

> **APK Android**: Tải từ [hoiucnro.com](https://hoiucnro.com) hoặc dùng APK đã cài sẵn.  
> **Barcoll [HUNR].rar** là Windows `.exe` – dùng để test trên PC.

---

## ⚙️ Thông tin kỹ thuật

| Mục | Giá trị |
|-----|---------|
| Game port | `14445` (TCP) |
| HTTP/Admin port | `1707` |
| Server list URL (sau patch) | `http://127.0.0.1:1707/lists.txt` |
| Database | `hunr_2026` (MariaDB root) |
| JAR | `HunrProvision-0.0.1-SNAPSHOT.jar` |
| Java | OpenJDK 17 |

## 🔧 Chi tiết kỹ thuật APK patch

| | Trước patch | Sau patch |
|--|------------|----------|
| URL fetch | `https://hoiucnro.com/server.txt` | `http://127.0.0.1:1707/lists.txt` |
| File patched | `global-metadata.dat` (IL2CPP) | same |
| Chuỗi cũ | 31 bytes ASCII | — |
| Chuỗi mới | — | 31 bytes ASCII (khớp chính xác) |
| Ký | debug cert từ APK gốc | hunr-debug.keystore |

Không thay đổi logic game – chỉ đổi URL lấy danh sách server.

## 📁 Cấu trúc sau khi setup

```
~/hunr-server/
├── HunrProvision-0.0.1-SNAPSHOT.jar   # Server Spring Boot
├── application.properties              # Config local
├── static/
│   └── lists.txt                      # Server list cho APK: Local:127.0.0.1:14445:0,0,0
├── Config/                            # Config game
├── resources/                         # Assets game
├── logs/server.log
├── start.sh
├── stop.sh
├── hunr-debug.keystore                # Key ký APK
└── HUNR-offline.apk                   # APK đã patch (sau Menu 7)
```

## 🎮 Menu

```
1. Setup lần đầu
2. Khởi động server
3. Dừng server
4. Xem log (live)
5. MySQL shell
6. Thông tin server
7. 📱 Patch APK offline  ← Quan trọng!
0. Thoát
```

## ⚠️ Yêu cầu

- Android + Termux
- RAM ≥ 2GB free
- Storage ≥ 3GB
- Kết nối internet để tải lần đầu (setup)
- Sau đó: **chơi hoàn toàn offline** 🎉
