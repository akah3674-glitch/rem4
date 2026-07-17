#!/data/data/com.termux/files/usr/bin/bash
# ============================================================
#  Hồi Ức Ngọc Rồng (HUNR) – Termux Auto Setup v3.0
#  Repo  : https://github.com/akah3674-glitch/rem4
#  Author: akah3674-glitch
#  Note  : Chạy OFFLINE (local Spring Boot + APK patch)
# ============================================================

# ── Hằng số ─────────────────────────────────────────────────
SCRIPT_VERSION="3.0"
HUNR_DIR="$HOME/hunr-server"
SERVER_JAR="HunrProvision-0.0.1-SNAPSHOT.jar"
DRIVE_SERVER="1qQDKBYGRUxZma7Ax_8z1_v_s54_jAU09"
DB_NAME="hunr_2026"
GAME_PORT=14445
HTTP_PORT=1707
REPO_RAW="https://raw.githubusercontent.com/akah3674-glitch/rem4/main"

# APK patch (PHẢI khớp chính xác byte-for-byte, cùng 31 bytes)
APK_OLD_URL="https://hoiucnro.com/server.txt"
APK_NEW_URL="http://127.0.0.1:1707/lists.txt"

# ── Màu ─────────────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; BLUE='\033[0;34m'; NC='\033[0m'; BOLD='\033[1m'

# ── Detect CPU architecture (học từ DragonBoy_Termux) ───────
detect_arch() {
    CPU="$(getprop ro.product.cpu.abi 2>/dev/null)"
    case "$CPU" in
        arm64-v8a)                    ARCH="arm64"  ;;
        armeabi-v7a|armeabi)          ARCH="arm32"  ;;
        x86_64)                       ARCH="x86_64" ;;
        x86)  echo -e "${RED}Không hỗ trợ x86 32-bit!${NC}"; exit 1 ;;
        "")   ARCH="unknown" ;;
        *)    ARCH="$CPU"    ;;
    esac
}

# ── Auto cấp quyền lưu trữ (học từ DragonBoy_Termux) ───────
setup_storage() {
    if [ ! -d "$HOME/storage" ]; then
        echo -e "${CYAN}Cấp quyền lưu trữ Termux...${NC}"
        echo "Y" | termux-setup-storage &>/dev/null
        sleep 1
    fi
}

# ── Kiểm tra mạng ───────────────────────────────────────────
check_network() {
    if ! curl -sI --max-time 5 "https://github.com" &>/dev/null; then
        echo -e "${RED}✗ Không có mạng! Kiểm tra kết nối rồi thử lại.${NC}"
        return 1
    fi
    return 0
}

# ── Banner ──────────────────────────────────────────────────
print_banner() {
    clear
    echo -e "${CYAN}${BOLD}"
    echo "  ╔═══════════════════════════════════════════╗"
    echo "  ║   🐉  HỒI ỨC NGỌC RỒNG – HUNR Server     ║"
    echo "  ║       Termux Setup v${SCRIPT_VERSION} (Offline)       ║"
    echo "  ╚═══════════════════════════════════════════╝"
    echo -e "${NC}"
    # Trạng thái nhanh
    local status_srv status_db
    if [ -f "$HUNR_DIR/server.pid" ] && kill -0 "$(cat "$HUNR_DIR/server.pid" 2>/dev/null)" 2>/dev/null; then
        status_srv="${GREEN}● Đang chạy${NC}"
    else
        status_srv="${RED}● Dừng${NC}"
    fi
    if mysql -u root --connect-timeout=2 -e ";" 2>/dev/null; then
        status_db="${GREEN}● Online${NC}"
    else
        status_db="${RED}● Offline${NC}"
    fi
    echo -e "  Server: $status_srv    DB: $status_db    Arch: ${YELLOW}${ARCH:-?}${NC}"
    [ -f "$HUNR_DIR/$SERVER_JAR" ] && \
        echo -e "  JAR  : ${GREEN}✓ Đã cài${NC}" || \
        echo -e "  JAR  : ${RED}✗ Chưa cài (chọn 1)${NC}"
    echo ""
}

# ── Menu ────────────────────────────────────────────────────
print_menu() {
    echo -e "${BOLD}  ────────────────────────────────────────────${NC}"
    echo -e "  ${GREEN}1.${NC} Setup lần đầu  (tải server ~1GB + cài đặt)"
    echo -e "  ${GREEN}2.${NC} Khởi động server"
    echo -e "  ${GREEN}3.${NC} Dừng server"
    echo -e "  ${GREEN}4.${NC} Xem log server (live)"
    echo -e "  ${GREEN}5.${NC} Vào MySQL shell"
    echo -e "  ${GREEN}6.${NC} Thông tin server"
    echo -e "  ${YELLOW}7.${NC} 📱 Patch APK offline"
    echo -e "  ${BLUE}8.${NC} 🔄 Cập nhật script"
    echo -e "  ${GREEN}0.${NC} Thoát"
    echo -e "${BOLD}  ────────────────────────────────────────────${NC}"
    echo ""
}

# ── Kiểm tra & cài dependencies ─────────────────────────────
check_deps() {
    local missing=()
    for cmd in java mysqld curl python3; do
        command -v "$cmd" &>/dev/null || missing+=("$cmd")
    done
    if [ ${#missing[@]} -ne 0 ]; then
        echo -e "${YELLOW}⚙ Cài package thiếu: ${missing[*]}${NC}"
        pkg update -y -q 2>/dev/null
        pkg install -y openjdk-17 mariadb curl python3 2>/dev/null || true
        echo -e "${GREEN}✓ Xong${NC}"
    fi
}

# ── Tải HUNR_Server.zip từ Google Drive ─────────────────────
# ZIP → /tmp (xoá sau extract) → chỉ giữ ~820MB cần thiết
# Bỏ: backup/202MB + _website/52MB + src + log → tiết kiệm ~255MB
download_server() {
    mkdir -p "$HUNR_DIR"
    if [ -f "$HUNR_DIR/$SERVER_JAR" ]; then
        echo -e "${GREEN}✓ Server đã tồn tại, bỏ qua tải${NC}"; return 0
    fi

    # ── Disclaimer trước khi tải 1GB (học từ DragonBoy) ─────
    echo -e "${YELLOW}"
    echo "  ┌─────────────────────────────────────────────┐"
    echo "  │  ⚠  LƯU Ý TRƯỚC KHI SETUP                  │"
    echo "  │                                              │"
    echo "  │  • Sẽ tải ~1.1GB từ Google Drive            │"
    echo "  │  • Cần thêm ~820MB dung lượng trống         │"
    echo "  │  • Cài MariaDB (~200MB) nếu chưa có         │"
    echo "  │  • Quá trình mất 15-40 phút (tuỳ mạng)      │"
    echo "  └─────────────────────────────────────────────┘"
    echo -e "${NC}"
    read -p "  Bạn có muốn tiếp tục? [Y/N]: " confirm
    [[ "$confirm" =~ ^[Yy]$ ]] || { echo "Huỷ."; return 1; }
    echo ""

    check_network || return 1
    check_deps

    local ZIP="/tmp/HUNR_Server.zip"
    local URL="https://drive.usercontent.google.com/download?id=${DRIVE_SERVER}&export=download&authuser=0&confirm=t"

    echo -e "${CYAN}━━ Bước 1/3: Tải HUNR_Server.zip ━━━━━━━━━━━━${NC}"
    if [ -f "$ZIP" ]; then
        echo -e "  ${YELLOW}↻ Tiếp tục tải dở...${NC}"
        curl -L --max-redirs 15 -A "Mozilla/5.0" -C - "$URL" --output "$ZIP" --progress-bar
    else
        curl -L --max-redirs 15 -A "Mozilla/5.0" "$URL" --output "$ZIP" --progress-bar
    fi
    echo ""

    # Kiểm tra ZIP hợp lệ
    if ! python3 -c "import zipfile; zipfile.ZipFile('$ZIP')" 2>/dev/null; then
        echo -e "${RED}✗ File ZIP lỗi hoặc chưa tải xong!${NC}"
        rm -f "$ZIP"; return 1
    fi

    echo -e "${CYAN}━━ Bước 2/3: Extract file cần thiết ━━━━━━━━━━${NC}"
    echo -e "  (Bỏ qua backup/src/website để tiết kiệm ~255MB)"
    python3 << PYEOF
import zipfile, os, shutil, sys

zip_path = "$ZIP"
out_dir  = "$HUNR_DIR"
jar_dest = os.path.join(out_dir, "$SERVER_JAR")

SKIP = [
    "Hunr2026/backup/",
    "Hunr2026/_website/",
    "Hunr2026/src/",
    "Hunr2026/log/",
    "Hunr2026/.mvn/",
    "Hunr2026/replay_",
    "Hunr2026/hs_err_",
    "Hunr2026/LogThoiVang",
    "Hunr2026/MultiLayerLog",
    "Hunr2026/ConfigNRO.exe",
    "Hunr2026/target/classes/",
    "Hunr2026/target/maven-",
    "Hunr2026/target/generated-",
    "Hunr2026/target/surefire",
    "Hunr2026/target/test-",
]
JAR_IN_ZIP = "Hunr2026/target/HunrProvision-0.0.1-SNAPSHOT.jar"

total = extracted = skipped = 0
try:
    with zipfile.ZipFile(zip_path) as z:
        entries = z.infolist()
        total = len(entries)
        for i, info in enumerate(entries):
            fn = info.filename
            if fn.endswith("/"):
                continue
            if any(fn.startswith(s) or fn == s.rstrip("/") for s in SKIP):
                skipped += info.compress_size
                continue
            if fn == JAR_IN_ZIP:
                print(f"  Extracting JAR ({info.compress_size/1024/1024:.0f}MB)...")
                with z.open(info) as src, open(jar_dest, "wb") as dst:
                    shutil.copyfileobj(src, dst)
                extracted += info.compress_size
                continue
            rel = fn.replace("Hunr2026/", "", 1)
            dest = os.path.join(out_dir, rel)
            os.makedirs(os.path.dirname(dest), exist_ok=True)
            with z.open(info) as src, open(dest, "wb") as dst:
                shutil.copyfileobj(src, dst)
            extracted += info.compress_size
            if i % 300 == 0:
                print(f"  [{i}/{total}] {extracted/1024/1024:.0f}MB extracted, {skipped/1024/1024:.0f}MB skipped")

    print(f"\n  ✓ Extracted: {extracted/1024/1024:.0f}MB | Bỏ qua: {skipped/1024/1024:.0f}MB")
except Exception as e:
    print(f"Lỗi: {e}", file=sys.stderr)
    sys.exit(1)
PYEOF
    local py_exit=$?
    rm -f "$ZIP"
    echo -e "  ${GREEN}✓ Đã xoá ZIP tạm${NC}"
    [ $py_exit -ne 0 ] && { echo -e "${RED}✗ Extract thất bại!${NC}"; return 1; }
    [ ! -f "$HUNR_DIR/$SERVER_JAR" ] && { echo -e "${RED}✗ Không tìm thấy JAR!${NC}"; return 1; }
    echo ""
}

# ── Khởi tạo MySQL ──────────────────────────────────────────
setup_mysql() {
    echo -e "${CYAN}━━ Bước 3/3: Khởi tạo MySQL ━━━━━━━━━━━━━━━━━${NC}"
    if ! mysql -u root --connect-timeout=3 -e ";" 2>/dev/null; then
        echo -e "  Khởi động MySQL lần đầu..."
        mysql_install_db 2>/dev/null || true
        mysqld_safe --user=root &>/dev/null &
        sleep 4
    fi
    mysql -u root --connect-timeout=5 -e "
        CREATE DATABASE IF NOT EXISTS \`$DB_NAME\` CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
        ALTER USER 'root'@'localhost' IDENTIFIED BY '';
        FLUSH PRIVILEGES;
    " 2>/dev/null || true
    echo -e "  ${GREEN}✓ Database '$DB_NAME' sẵn sàng${NC}"
}

# ── Tạo application.properties ──────────────────────────────
write_config() {
    echo -e "  Ghi cấu hình Spring Boot..."
    mkdir -p "$HUNR_DIR/static"

    cat > "$HUNR_DIR/application.properties" << EOF
# HUNR Server Config – tự động tạo bởi hunr_setup.sh
server.port=${HTTP_PORT}
server.address=0.0.0.0

# Database
spring.datasource.url=jdbc:mariadb://localhost:3306/${DB_NAME}?useUnicode=true&characterEncoding=utf8mb4&serverTimezone=Asia/Ho_Chi_Minh
spring.datasource.username=root
spring.datasource.password=
spring.datasource.driver-class-name=org.mariadb.jdbc.Driver
spring.jpa.hibernate.ddl-auto=update
spring.jpa.database-platform=org.hibernate.dialect.MariaDBDialect

# Static files (phục vụ lists.txt cho APK)
spring.web.resources.static-locations=file:${HUNR_DIR}/static/

# Game server port (TCP)
game.server.port=${GAME_PORT}
EOF

    # Tạo lists.txt cho APK offline
    echo "Local:127.0.0.1:${GAME_PORT}:0,0,0" > "$HUNR_DIR/static/lists.txt"
    echo -e "  ${GREEN}✓ Config + lists.txt sẵn sàng${NC}"
}

# ── Full setup ───────────────────────────────────────────────
do_setup() {
    download_server || return
    setup_mysql
    write_config
    echo ""
    echo -e "${GREEN}${BOLD}  ✅ Setup hoàn tất!${NC}"
    echo -e "  Chọn ${BOLD}2${NC} để khởi động server"
    echo -e "  Chọn ${BOLD}7${NC} để patch APK chạy offline"
    echo ""
}

# ── Khởi động server ────────────────────────────────────────
start_server() {
    if [ ! -f "$HUNR_DIR/$SERVER_JAR" ]; then
        echo -e "${RED}✗ Chưa setup! Chọn menu 1 trước.${NC}"; return
    fi
    if [ -f "$HUNR_DIR/server.pid" ] && kill -0 "$(cat "$HUNR_DIR/server.pid" 2>/dev/null)" 2>/dev/null; then
        echo -e "${YELLOW}⚠ Server đang chạy (PID=$(cat "$HUNR_DIR/server.pid"))${NC}"; return
    fi
    # Đảm bảo MySQL đang chạy
    mysql -u root --connect-timeout=2 -e ";" 2>/dev/null || {
        echo -e "${CYAN}Khởi động MySQL...${NC}"
        mysqld_safe --user=root &>/dev/null &
        sleep 3
    }
    echo -e "${CYAN}Khởi động HUNR Server...${NC}"
    cd "$HUNR_DIR"
    nohup java -jar "$HUNR_DIR/$SERVER_JAR" \
        --spring.config.location="$HUNR_DIR/application.properties" \
        > "$HUNR_DIR/server.log" 2>&1 &
    echo $! > "$HUNR_DIR/server.pid"
    sleep 3
    if kill -0 "$(cat "$HUNR_DIR/server.pid" 2>/dev/null)" 2>/dev/null; then
        echo -e "${GREEN}✓ Server đang chạy (PID=$(cat "$HUNR_DIR/server.pid"))${NC}"
        echo -e "  Game : 127.0.0.1:${GAME_PORT}"
        echo -e "  HTTP : http://127.0.0.1:${HTTP_PORT}"
    else
        echo -e "${RED}✗ Server khởi động thất bại! Xem log:${NC}"
        tail -20 "$HUNR_DIR/server.log"
    fi
}

# ── Dừng server ─────────────────────────────────────────────
stop_server() {
    if [ ! -f "$HUNR_DIR/server.pid" ]; then
        echo -e "${YELLOW}Server chưa chạy.${NC}"; return
    fi
    local pid
    pid="$(cat "$HUNR_DIR/server.pid" 2>/dev/null)"
    if kill -0 "$pid" 2>/dev/null; then
        kill "$pid"
        sleep 2
        kill -0 "$pid" 2>/dev/null && kill -9 "$pid" 2>/dev/null
        echo -e "${GREEN}✓ Server đã dừng${NC}"
    else
        echo -e "${YELLOW}Server không còn chạy.${NC}"
    fi
    rm -f "$HUNR_DIR/server.pid"
}

# ── Xem log ─────────────────────────────────────────────────
show_log() {
    if [ ! -f "$HUNR_DIR/server.log" ]; then
        echo -e "${YELLOW}Chưa có log. Khởi động server trước.${NC}"; return
    fi
    echo -e "${CYAN}Log server (Ctrl+C để thoát):${NC}"
    tail -f "$HUNR_DIR/server.log"
}

# ── Thông tin ───────────────────────────────────────────────
show_info() {
    echo -e "\n${CYAN}${BOLD}  ═══ THÔNG TIN HUNR SERVER ═══${NC}"
    echo -e "  Script  : v${SCRIPT_VERSION}"
    echo -e "  CPU Arch: ${ARCH:-không rõ}"
    echo -e "  JAR     : $HUNR_DIR/$SERVER_JAR"
    echo -e "  Config  : $HUNR_DIR/application.properties"
    echo -e "  Log     : $HUNR_DIR/server.log"
    echo -e "  DB      : $DB_NAME  (port 3306)"
    echo -e "  Game    : 127.0.0.1:${GAME_PORT}"
    echo -e "  HTTP    : http://127.0.0.1:${HTTP_PORT}"
    echo -e "  Lists   : http://127.0.0.1:${HTTP_PORT}/lists.txt"
    echo ""
    if [ -f "$HUNR_DIR/server.pid" ] && kill -0 "$(cat "$HUNR_DIR/server.pid" 2>/dev/null)" 2>/dev/null; then
        echo -e "  Server : ${GREEN}● ĐANG CHẠY${NC}  PID=$(cat "$HUNR_DIR/server.pid")"
    else
        echo -e "  Server : ${RED}● KHÔNG CHẠY${NC}"
    fi
    if mysql -u root --connect-timeout=3 -e "USE $DB_NAME;" 2>/dev/null; then
        local tcount
        tcount=$(mysql -u root -se "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema='$DB_NAME';" 2>/dev/null)
        echo -e "  MySQL  : ${GREEN}● ONLINE${NC}  ($tcount bảng)"
    else
        echo -e "  MySQL  : ${RED}● OFFLINE${NC}"
    fi
    echo ""
}

# ── Patch APK offline ───────────────────────────────────────
do_patch_apk() {
    echo -e "\n${CYAN}${BOLD}  ═══ PATCH APK OFFLINE ═══${NC}"
    echo -e "  Thay URL server trong APK:"
    echo -e "    Cũ: ${RED}${APK_OLD_URL}${NC}"
    echo -e "    Mới: ${GREEN}${APK_NEW_URL}${NC}"
    echo ""

    read -p "  Nhập đường dẫn APK gốc: " APK_IN
    APK_IN="${APK_IN//\'/}"   # strip quotes
    APK_IN="${APK_IN// /\ }"
    [ -f "$APK_IN" ] || { echo -e "${RED}✗ Không tìm thấy file: $APK_IN${NC}"; return; }

    local APK_OUT="$HUNR_DIR/HUNR-offline.apk"
    local WORK="/tmp/hunr_apk_patch"
    rm -rf "$WORK"; mkdir -p "$WORK"

    echo -e "  ${CYAN}Đang patch global-metadata.dat...${NC}"
    python3 << PYEOF
import zipfile, shutil, os, sys

apk_in  = r"$APK_IN"
apk_out = r"$APK_OUT"
work    = r"$WORK"
old_url = b"$APK_OLD_URL"
new_url = b"$APK_NEW_URL"

# Tìm global-metadata.dat trong APK
META_PATH = None
with zipfile.ZipFile(apk_in) as z:
    for name in z.namelist():
        if "global-metadata.dat" in name:
            META_PATH = name
            break

if not META_PATH:
    print("  ✗ Không tìm thấy global-metadata.dat trong APK!", file=sys.stderr)
    sys.exit(1)

print(f"  Tìm thấy: {META_PATH}")

# Extract metadata
meta_tmp = os.path.join(work, "global-metadata.dat")
with zipfile.ZipFile(apk_in) as z:
    with z.open(META_PATH) as src, open(meta_tmp, "wb") as dst:
        shutil.copyfileobj(src, dst)

# Patch URL
data = open(meta_tmp, "rb").read()
if old_url not in data:
    print(f"  ✗ Không tìm thấy URL cần patch:\n    {old_url}", file=sys.stderr)
    sys.exit(1)

count = data.count(old_url)
data_patched = data.replace(old_url, new_url)
open(meta_tmp, "wb").write(data_patched)
print(f"  ✓ Đã patch {count} chỗ")

# Rebuild APK (copy gốc, thay metadata)
shutil.copy2(apk_in, apk_out)
import subprocess
result = subprocess.run(
    ["zip", "-j", apk_out, meta_tmp],
    capture_output=True
)
if result.returncode != 0:
    # Fallback: dùng Python zipfile update
    import tempfile
    tmp_apk = apk_out + ".tmp"
    with zipfile.ZipFile(apk_in, "r") as zin, zipfile.ZipFile(tmp_apk, "w", zipfile.ZIP_DEFLATED) as zout:
        for item in zin.infolist():
            if item.filename == META_PATH:
                zout.write(meta_tmp, META_PATH)
            else:
                zout.writestr(item, zin.read(item.filename))
    os.replace(tmp_apk, apk_out)

print(f"  ✓ APK patched: {apk_out}")
PYEOF
    [ $? -ne 0 ] && { echo -e "${RED}✗ Patch thất bại!${NC}"; return; }

    # ── Ký lại APK ──────────────────────────────────────────
    echo -e "  ${CYAN}Ký lại APK...${NC}"
    local KEYSTORE="$HUNR_DIR/hunr-debug.keystore"
    if [ ! -f "$KEYSTORE" ]; then
        keytool -genkeypair -v \
            -keystore "$KEYSTORE" \
            -alias hunr -keyalg RSA -keysize 2048 \
            -validity 10000 \
            -storepass hunrpass -keypass hunrpass \
            -dname "CN=HUNR,OU=Dev,O=HUNR,L=VN,ST=VN,C=VN" 2>/dev/null
    fi
    jarsigner -verbose \
        -keystore "$KEYSTORE" \
        -storepass hunrpass -keypass hunrpass \
        -sigalg SHA1withRSA -digestalg SHA1 \
        "$APK_OUT" hunr 2>&1 | grep -E "jar signed|signing|warning" || true

    # ── Copy ra game_download (học từ DragonBoy) ────────────
    local DL_DIR="$HOME/storage/downloads"
    if [ -d "$DL_DIR" ]; then
        cp "$APK_OUT" "$DL_DIR/HUNR-offline.apk" 2>/dev/null && \
            echo -e "  ${GREEN}✓ Copy → Thư mục Tải xuống/HUNR-offline.apk${NC}"
    fi

    echo ""
    echo -e "${GREEN}  ✅ APK đã patch xong!${NC}"
    echo -e "  File: ${BOLD}$APK_OUT${NC}"
    [ -d "$DL_DIR" ] && echo -e "  SD  : ${BOLD}$DL_DIR/HUNR-offline.apk${NC}"
    echo ""
    echo -e "  ${YELLOW}Lưu ý:${NC} Cài APK này và BẬT server (menu 2) trước khi vào game!"
}

# ── Cập nhật script (học từ khanhupdate.sh pattern) ─────────
do_update() {
    check_network || return
    echo -e "${CYAN}Kiểm tra cập nhật...${NC}"
    local TMP="/tmp/hunr_setup_new.sh"
    curl -L --max-redirs 15 --progress-bar \
        "${REPO_RAW}/hunr_setup.sh" --output "$TMP" 2>/dev/null
    if [ ! -s "$TMP" ]; then
        echo -e "${RED}✗ Tải thất bại!${NC}"; return
    fi
    local new_ver
    new_ver=$(grep 'SCRIPT_VERSION=' "$TMP" | head -1 | cut -d'"' -f2)
    if [ "$new_ver" = "$SCRIPT_VERSION" ]; then
        echo -e "${GREEN}✓ Đang dùng phiên bản mới nhất (v${SCRIPT_VERSION})${NC}"
        rm -f "$TMP"; return
    fi
    echo -e "  Phiên bản hiện tại : v${SCRIPT_VERSION}"
    echo -e "  Phiên bản mới      : v${new_ver}"
    read -p "  Cập nhật? [Y/N]: " confirm
    [[ "$confirm" =~ ^[Yy]$ ]] || { rm -f "$TMP"; return; }
    local SELF
    SELF="$(readlink -f "$0" 2>/dev/null || echo "$0")"
    cp "$TMP" "$SELF" && chmod 755 "$SELF"
    rm -f "$TMP"
    echo -e "${GREEN}✓ Đã cập nhật lên v${new_ver}! Chạy lại script.${NC}"
    exit 0
}

# ── MAIN ────────────────────────────────────────────────────
main() {
    # Fix curl|bash stdin bug: exec < /dev/tty để đọc từ terminal
    exec < /dev/tty

    # Setup một lần khi khởi động
    detect_arch
    setup_storage

    print_banner
    while true; do
        print_menu
        read -p "  Chọn [0-8]: " choice
        echo ""
        case "$choice" in
            1) do_setup       ;;
            2) start_server   ;;
            3) stop_server    ;;
            4) show_log       ;;
            5) mysql -u root "$DB_NAME" 2>/dev/null || mysql -u root 2>/dev/null ;;
            6) show_info      ;;
            7) do_patch_apk   ;;
            8) do_update      ;;
            0) echo -e "${GREEN}  Thoát. Chúc chơi vui! 🐉${NC}"; exit 0 ;;
            *) echo -e "${RED}  Lựa chọn không hợp lệ!${NC}" ;;
        esac
        echo ""
        read -p "  [Enter để tiếp tục]" _
        print_banner
    done
}

main "$@"
