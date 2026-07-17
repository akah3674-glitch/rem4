#!/data/data/com.termux/files/usr/bin/bash
# ╔══════════════════════════════════════════════════════════════════╗
# ║   Hồi Ức Ngọc Rồng – Private Server Offline (Termux)           ║
# ║   Spring Boot + MariaDB + APK patch tự động                    ║
# ╚══════════════════════════════════════════════════════════════════╝
set -euo pipefail

R='\033[1;31m' G='\033[1;32m' Y='\033[1;33m'
B='\033[1;34m' C='\033[1;36m' W='\033[1;37m' N='\033[0m'
ok()  { echo -e "${G}[✓]${N} $*"; }
err() { echo -e "${R}[✗]${N} $*"; }
inf() { echo -e "${B}[i]${N} $*"; }
wrn() { echo -e "${Y}[!]${N} $*"; }
die() { err "$*"; exit 1; }

# ─── cấu hình ─────────────────────────────────────────────────────
HUNR_HOME="$HOME/hunr-server"
STATIC_DIR="$HUNR_HOME/static"
APK_DIR="$HOME/storage/downloads"
APK_OUT="$APK_DIR/HUNR_Local.apk"

DRIVE_SERVER="1qQDKBYGRUxZma7Ax_8z1_v_s54_jAU09"   # Server ZIP ~1.1GB

DB_NAME="hunr_2026"
HTTP_PORT="1707"
GAME_PORT="14445"

# Patch strings – phải đúng 31 bytes mỗi bên (đã test & xác nhận)
OLD_URL="https://hoiucnro.com/server.txt"    # 31 bytes
NEW_URL="http://127.0.0.1:${HTTP_PORT}/lists.txt"  # 31 bytes

KEYSTORE="$HOME/.hunr_sign.keystore"
KEY_ALIAS="hunrsign"
KEY_PASS="hunr12345"
HUNR_PKG="com.hoiucnro.game"
SETUP_FLAG="$HUNR_HOME/.setup_done"

banner() {
  clear
  echo -e "${C}"
  echo "  ██╗  ██╗██╗   ██╗███╗   ██╗██████╗ "
  echo "  ██║  ██║██║   ██║████╗  ██║██╔══██╗"
  echo "  ███████║██║   ██║██╔██╗ ██║██████╔╝"
  echo "  ██╔══██║██║   ██║██║╚██╗██║██╔══██╗"
  echo "  ██║  ██║╚██████╔╝██║ ╚████║██║  ██║"
  echo "  ╚═╝  ╚═╝ ╚═════╝ ╚═╝  ╚═══╝╚═╝  ╚═╝"
  echo -e "${Y}    Hồi Ức Ngọc Rồng – Private Server Offline${N}"
  echo -e "${G}  ═══════════════════════════════════════════════${N}"
  echo ""
}

# ══════════════════════════════════════════════════════════════════
# BƯỚC 1: Cài packages
# ══════════════════════════════════════════════════════════════════
step_packages() {
  inf "Cập nhật pkg list..."
  pkg update -y 2>/dev/null | tail -2 || true

  inf "Cài packages..."
  pkg install -y curl wget python python-pip \
    openjdk-17 mariadb openssl zip unzip \
    termux-tools 2>/dev/null | grep -E "^(Install|Unpacking|Setting)" || true

  pip install -q gdown requests 2>/dev/null || true
  ok "Packages OK"
}

# ══════════════════════════════════════════════════════════════════
# BƯỚC 2: Setup MariaDB
# ══════════════════════════════════════════════════════════════════
step_mariadb() {
  mkdir -p "$HUNR_HOME"
  if [[ ! -d "$PREFIX/var/lib/mysql/mysql" ]]; then
    mysql_install_db --datadir="$PREFIX/var/lib/mysql" 2>/dev/null | tail -3 || true
  fi
  _start_mariadb
  mysql -u root -e "
    CREATE DATABASE IF NOT EXISTS \`$DB_NAME\`
      CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
    GRANT ALL PRIVILEGES ON \`$DB_NAME\`.* TO 'root'@'localhost';
    FLUSH PRIVILEGES;" 2>/dev/null || wrn "DB có thể đã tồn tại"
  ok "Database '$DB_NAME' OK"
}

_start_mariadb() {
  if mysqladmin -u root ping &>/dev/null 2>&1; then
    ok "MariaDB: đang chạy"; return 0
  fi
  mysqladmin -u root shutdown 2>/dev/null || true
  sleep 1
  mysqld_safe \
    --datadir="$PREFIX/var/lib/mysql" \
    --socket="$PREFIX/tmp/mysql.sock" \
    --pid-file="$PREFIX/tmp/mysqld.pid" \
    --log-error="$PREFIX/tmp/mysqld.err" \
    --skip-networking=0 --bind-address=127.0.0.1 --port=3306 \
    &>/dev/null &
  disown $! 2>/dev/null || true
  local tries=0
  while ! mysqladmin -u root ping &>/dev/null 2>&1; do
    sleep 1; tries=$((tries+1))
    [[ $tries -ge 25 ]] && die "MariaDB không khởi động!"
  done
  ok "MariaDB: Running"
}

# ══════════════════════════════════════════════════════════════════
# BƯỚC 3: Tải + setup HUNR Server
# ══════════════════════════════════════════════════════════════════
step_server() {
  mkdir -p "$HUNR_HOME" "$STATIC_DIR"
  local jar
  jar=$(find "$HUNR_HOME" -maxdepth 2 -name "*.jar" 2>/dev/null | head -1)

  if [[ -n "$jar" ]]; then
    ok "Server JAR đã có: $(basename "$jar")"
  else
    inf "Tải HUNR_Server.zip từ Google Drive (~1.1GB)..."
    _gdrive_download "$DRIVE_SERVER" "/tmp/HUNR_Server.zip"

    local fsize
    fsize=$(stat -c%s "/tmp/HUNR_Server.zip" 2>/dev/null || echo 0)
    [[ "$fsize" -lt 1000000 ]] && die "Server ZIP không hợp lệ (${fsize} bytes)"

    inf "Giải nén..."
    unzip -q "/tmp/HUNR_Server.zip" -d "/tmp/hunr_extract/" 2>/dev/null || \
      unzip "/tmp/HUNR_Server.zip" -d "/tmp/hunr_extract/"

    local extracted_jar
    extracted_jar=$(find "/tmp/hunr_extract/" -name "*.jar" \
      -not -name "*sources*" -not -name "*javadoc*" 2>/dev/null | head -1)

    if [[ -n "$extracted_jar" ]]; then
      cp "$extracted_jar" "$HUNR_HOME/"
      ok "JAR: $(basename "$extracted_jar")"
    else
      cp -r /tmp/hunr_extract/*/* "$HUNR_HOME/" 2>/dev/null || \
        cp -r /tmp/hunr_extract/* "$HUNR_HOME/"
      wrn "Không tìm thấy JAR rõ ràng – copy toàn bộ vào $HUNR_HOME/"
    fi
    rm -rf /tmp/HUNR_Server.zip /tmp/hunr_extract/ 2>/dev/null || true
  fi

  # Serve cả server.txt và lists.txt – APK gốc dùng server.txt, APK patch dùng lists.txt
  local ADDR="Local:127.0.0.1:${GAME_PORT}:0,0,0"
  echo "$ADDR" > "$STATIC_DIR/server.txt"
  echo "$ADDR" > "$STATIC_DIR/lists.txt"
  ok "Static: server.txt + lists.txt → $ADDR"

  cat > "$HUNR_HOME/application.properties" << APPEOF
server.port=${HTTP_PORT}
spring.datasource.url=jdbc:mysql://127.0.0.1:3306/${DB_NAME}?useSSL=false&allowPublicKeyRetrieval=true&serverTimezone=Asia/Ho_Chi_Minh&characterEncoding=utf8mb4
spring.datasource.username=root
spring.datasource.password=
spring.datasource.driver-class-name=com.mysql.cj.jdbc.Driver
spring.jpa.hibernate.ddl-auto=update
spring.jpa.show-sql=false
spring.jpa.properties.hibernate.dialect=org.hibernate.dialect.MySQL8Dialect
spring.web.resources.static-locations=file:${HUNR_HOME}/static/,classpath:/static/
spring.mvc.static-path-pattern=/**
logging.level.root=WARN
logging.level.com.hunr=INFO
APPEOF
  ok "application.properties OK"

  mkdir -p "$HUNR_HOME/bin"
  _create_start_script
}

_gdrive_download() {
  local drive_id="$1" out="$2"
  if python3 -c "import gdown" &>/dev/null 2>&1; then
    python3 -c "
import gdown, sys
try:
    gdown.download(id='$drive_id', output='$out', quiet=False)
    print('OK')
except Exception as e:
    print(f'ERR:{e}'); sys.exit(1)
" && return 0
  fi
  wrn "gdown không dùng được, thử curl..."
  local COOKIE="/tmp/gdcookie_$$.txt"
  curl -sc "$COOKIE" "https://drive.google.com/uc?export=download&id=$drive_id" \
    -o /tmp/gd_check_$$.html 2>/dev/null
  local CONFIRM
  CONFIRM=$(grep -oP '(?<=confirm=)[^&"]+' /tmp/gd_check_$$.html 2>/dev/null | head -1)
  if [[ -n "$CONFIRM" ]]; then
    curl -Lb "$COOKIE" \
      "https://drive.google.com/uc?export=download&confirm=${CONFIRM}&id=$drive_id" \
      -o "$out" --progress-bar
  else
    curl -L \
      "https://drive.google.com/uc?export=download&id=$drive_id&confirm=t&uuid=$(date +%s)" \
      -o "$out" --progress-bar
  fi
  rm -f "/tmp/gdcookie_$$.txt" "/tmp/gd_check_$$.html" 2>/dev/null || true
}

# ══════════════════════════════════════════════════════════════════
# BƯỚC 4: Lấy APK gốc Android
# ══════════════════════════════════════════════════════════════════
step_get_apk() {
  echo ""
  echo -e "${W}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${N}"
  echo -e "${Y}  Cần APK Android của Hồi Ức Ngọc Rồng${N}"
  echo -e "${W}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${N}"
  echo ""
  echo -e "  ${C}[1]${N} Tự động lấy từ app đã cài trên máy"
  echo -e "  ${C}[2]${N} Nhập đường dẫn APK thủ công"
  echo -e "  ${C}[3]${N} Hướng dẫn tải APK"
  echo ""
  read -p "$(echo -e "${C}Chọn [1/2/3]: ${N}")" apk_choice
  exec </dev/tty

  local apk_raw="/tmp/hunr_original.apk"

  case "$apk_choice" in
    1)
      inf "Tìm APK đã cài..."
      local apk_path=""
      for pkg in "$HUNR_PKG" com.hoiucnro com.hunr.game vn.hoiucnro.game; do
        apk_path=$(pm path "$pkg" 2>/dev/null | sed 's/package://' | tr -d '[:space:]') || true
        [[ -n "$apk_path" ]] && break
      done
      if [[ -n "$apk_path" && -f "$apk_path" ]]; then
        cp "$apk_path" "$apk_raw"
        ok "Lấy APK từ: $apk_path"
      else
        err "Không tìm thấy HUNR đã cài!"
        echo -e "  ${Y}→ Hãy tải APK trước (chọn [3] để xem hướng dẫn)${N}"
        read -p "$(echo -e "${Y}Nhấn Enter thoát...${N}")" _; exec </dev/tty
        exit 1
      fi
      ;;
    2)
      echo ""
      echo -e "  ${C}Ví dụ: /sdcard/Download/HoiUcNgocRong.apk${N}"
      read -p "$(echo -e "${C}Đường dẫn APK: ${N}")" user_apk
      exec </dev/tty
      user_apk="${user_apk/#\~/$HOME}"
      [[ ! -f "$user_apk" ]] && die "Không tìm thấy: $user_apk"
      cp "$user_apk" "$apk_raw"
      ok "APK gốc: $(du -h "$apk_raw" | cut -f1)"
      ;;
    3)
      echo ""
      echo -e "${W}  Cách lấy APK Android của Hồi Ức Ngọc Rồng:${N}"
      echo -e "  ${Y}1.${N} Tải từ: https://hoiucnro.com"
      echo -e "  ${Y}2.${N} Hoặc tìm 'Hoi Uc Ngoc Rong APK' trên apkpure.com"
      echo -e "  ${Y}3.${N} Lưu file vào /sdcard/Download/"
      echo -e "  ${Y}4.${N} Chạy lại script, chọn [2]"
      echo ""
      read -p "$(echo -e "${G}Nhấn Enter thoát...${N}")" _; exec </dev/tty
      exit 0
      ;;
    *)
      die "Chọn không hợp lệ"
      ;;
  esac

  local fsize
  fsize=$(stat -c%s "$apk_raw" 2>/dev/null || echo 0)
  [[ "$fsize" -lt 500000 ]] && die "APK không hợp lệ (${fsize} bytes)"
  echo "$apk_raw"
}

# ══════════════════════════════════════════════════════════════════
# BƯỚC 5: Patch APK – thay URL server → localhost
# URL đã xác nhận qua test: 31 bytes → 31 bytes (khớp chính xác)
# OLD: https://hoiucnro.com/server.txt  (31 bytes)
# NEW: http://127.0.0.1:1707/lists.txt  (31 bytes)
# ══════════════════════════════════════════════════════════════════
step_patch_apk() {
  local apk_in="$1"
  local apk_out="/tmp/hunr_patched.apk"

  inf "Patch URL: hoiucnro.com/server.txt → 127.0.0.1:${HTTP_PORT}/lists.txt ..."

  python3 << PYEOF
import sys, zipfile, os, shutil

apk_in  = "$apk_in"
apk_out = "$apk_out"

OLD = b"https://hoiucnro.com/server.txt"   # 31 bytes – đã xác nhận
NEW = b"http://127.0.0.1:${HTTP_PORT}/lists.txt"  # 31 bytes – khớp chính xác

assert len(OLD) == len(NEW), f"Độ dài không khớp! {len(OLD)} vs {len(NEW)}"

META_PATHS = [
    "assets/bin/Data/Managed/Metadata/global-metadata.dat",
    "assets/bin/Data/il2cpp_data/Metadata/global-metadata.dat",
]

def find_meta(zin):
    names = zin.namelist()
    for p in META_PATHS:
        if p in names: return p
    cands = [n for n in names if "global-metadata" in n.lower()]
    return cands[0] if cands else None

with zipfile.ZipFile(apk_in, 'r') as zin:
    meta_path = find_meta(zin)
    if not meta_path:
        print("[✗] Không tìm thấy global-metadata.dat trong APK!")
        print("     APK này có thể không phải HUNR hoặc là split APK")
        sys.exit(1)
    print(f"  [i] Metadata: {meta_path}")
    data = zin.read(meta_path)

print(f"  [i] Metadata size: {len(data):,} bytes")

if OLD not in data:
    print(f"  [!] Không tìm thấy URL gốc: {OLD.decode()}")
    print(f"  [!] APK này có thể đã patch hoặc khác phiên bản")
    sys.exit(1)

count = data.count(OLD)
patched = data.replace(OLD, NEW)
print(f"  [✓] Đã thay {count} lần")
print(f"      {OLD.decode()} →")
print(f"      {NEW.decode()}")

# Ghi APK mới (copy toàn bộ, chỉ thay metadata)
with zipfile.ZipFile(apk_in, 'r') as zin, \
     zipfile.ZipFile(apk_out, 'w', zipfile.ZIP_DEFLATED, compresslevel=6) as zout:
    for item in zin.infolist():
        raw = zin.read(item.filename)
        if item.filename == meta_path:
            zout.writestr(item, patched)
        else:
            zout.writestr(item, raw)

print(f"[✓] Patch xong: {apk_out}")
PYEOF

  [[ ! -f "$apk_out" ]] && die "Patch APK thất bại!"
  ok "Patch xong"
  echo "$apk_out"
}

# ══════════════════════════════════════════════════════════════════
# BƯỚC 6: Ký APK (bắt buộc sau khi sửa metadata)
# ══════════════════════════════════════════════════════════════════
step_sign_apk() {
  local apk_in="$1"

  if [[ ! -f "$KEYSTORE" ]]; then
    inf "Tạo keystore..."
    keytool -genkeypair -v \
      -keystore "$KEYSTORE" -alias "$KEY_ALIAS" \
      -keyalg RSA -keysize 2048 -validity 9999 \
      -dname "CN=HUNR Local,O=HUNR,C=VN" \
      -storepass "$KEY_PASS" -keypass "$KEY_PASS" \
      2>/dev/null && ok "Keystore OK" || wrn "Keystore lỗi nhỏ"
  fi

  inf "Ký APK..."
  jarsigner \
    -keystore "$KEYSTORE" \
    -storepass "$KEY_PASS" -keypass "$KEY_PASS" \
    -digestalg SHA-256 -sigalg SHA256withRSA \
    "$apk_in" "$KEY_ALIAS" 2>/dev/null && ok "Ký APK OK" || wrn "jarsigner lỗi nhỏ"

  echo Y | termux-setup-storage 2>/dev/null || true
  mkdir -p "$APK_DIR"
  cp "$apk_in" "$APK_OUT"
  ok "APK đã lưu: $APK_OUT"
}

# ══════════════════════════════════════════════════════════════════
# Tạo start.sh / stop.sh
# ══════════════════════════════════════════════════════════════════
_create_start_script() {
  cat > "$HUNR_HOME/bin/start.sh" << STARTEOF
#!/data/data/com.termux/files/usr/bin/bash
HUNR_HOME="\$HOME/hunr-server"
HTTP_PORT="${HTTP_PORT}"
GAME_PORT="${GAME_PORT}"

R='\033[1;31m' G='\033[1;32m' Y='\033[1;33m' C='\033[1;36m' N='\033[0m'
ok()  { echo -e "\${G}[✓]\${N} \$*"; }
err() { echo -e "\${R}[✗]\${N} \$*"; }
inf() { echo -e "\${C}[i]\${N} \$*"; }

echo -e "\${Y}═══════════════════════════════════════════════${N}"
echo -e "\${Y}   Hồi Ức Ngọc Rồng – Offline Launcher        ${N}"
echo -e "\${Y}═══════════════════════════════════════════════${N}"
echo ""

if ! mysqladmin -u root ping &>/dev/null 2>&1; then
  inf "Khởi động MariaDB..."
  mysqld_safe \
    --datadir="\$PREFIX/var/lib/mysql" \
    --socket="\$PREFIX/tmp/mysql.sock" \
    --pid-file="\$PREFIX/tmp/mysqld.pid" \
    --skip-networking=0 --bind-address=127.0.0.1 --port=3306 \
    &>/dev/null &
  disown
  tries=0
  while ! mysqladmin -u root ping &>/dev/null 2>&1; do
    sleep 1; tries=\$((tries+1))
    [[ \$tries -ge 20 ]] && { err "MariaDB không chạy!"; exit 1; }
  done
fi
ok "MariaDB: Running"

JAR=\$(find "\$HUNR_HOME" -maxdepth 2 -name "*.jar" -not -name "*sources*" 2>/dev/null | head -1)
[[ -z "\$JAR" ]] && { err "Không tìm thấy JAR! ls \$HUNR_HOME"; exit 1; }

inf "Khởi động HUNR Server: \$(basename \$JAR)"
inf "  HTTP : 127.0.0.1:\${HTTP_PORT}"
inf "  Game : 127.0.0.1:\${GAME_PORT}"
echo ""

cd "\$HUNR_HOME"
java -jar "\$JAR" \
  --spring.config.location="file:\${HUNR_HOME}/application.properties" \
  2>&1 | tee "\$HUNR_HOME/server.log" &
JAVA_PID=\$!
disown \$JAVA_PID 2>/dev/null || true

sleep 3
# Kiểm tra server đã chạy chưa
if curl -s "http://127.0.0.1:\${HTTP_PORT}/server.txt" &>/dev/null; then
  echo ""
  ok "Server online! Kiểm tra:"
  echo -e "  \${G}curl http://127.0.0.1:\${HTTP_PORT}/server.txt\${N}"
  echo -e "  \${G}curl http://127.0.0.1:\${HTTP_PORT}/lists.txt\${N}"
else
  wrn "Server đang khởi động, đợi thêm 10-15 giây..."
fi
echo ""
echo -e "  \${C}Log: tail -f \$HUNR_HOME/server.log\${N}"
echo -e "  \${C}Dừng: bash \$HUNR_HOME/bin/stop.sh\${N}"
STARTEOF
  chmod +x "$HUNR_HOME/bin/start.sh"

  cat > "$HUNR_HOME/bin/stop.sh" << 'STOPEOF'
#!/data/data/com.termux/files/usr/bin/bash
echo "Dừng HUNR Server..."
pkill -f "HunrProvision" 2>/dev/null && echo "[✓] Spring Boot dừng" || true
pkill -f "hunr.*\.jar"   2>/dev/null || true
pkill -f "java.*jar"     2>/dev/null || true
mysqladmin -u root shutdown 2>/dev/null && echo "[✓] MariaDB dừng" || true
echo "Xong."
STOPEOF
  chmod +x "$HUNR_HOME/bin/stop.sh"

  cat > "$HOME/hunr.sh" << SHORTEOF
#!/data/data/com.termux/files/usr/bin/bash
exec bash "$HUNR_HOME/hunr_setup.sh" "\$@"
SHORTEOF
  chmod +x "$HOME/hunr.sh"
  ok "Scripts OK"
}

# ══════════════════════════════════════════════════════════════════
# ADMIN MENU
# ══════════════════════════════════════════════════════════════════
_mysql() { mysql -u root -h 127.0.0.1 "$DB_NAME" -e "$1" 2>/dev/null; }

admin_menu() {
  while true; do
    clear
    echo -e "${W}══════ ADMIN – Hồi Ức Ngọc Rồng ══════${N}"
    echo ""
    mysqladmin -u root ping &>/dev/null 2>&1 && \
      echo -e "  ${G}● DB: Online${N}" || echo -e "  ${R}● DB: Offline${N}"
    echo ""
    echo -e "  ${Y}[1]${N} Xem tài khoản"
    echo -e "  ${Y}[2]${N} Xem nhân vật"
    echo -e "  ${Y}[3]${N} Chạy SQL tuỳ ý"
    echo -e "  ${Y}[4]${N} Xem log server"
    echo -e "  ${Y}[0]${N} Quay lại"
    echo ""
    read -p "$(echo -e "${C}Chọn: ${N}")" ch; exec </dev/tty
    case "$ch" in
      1)
        _mysql "SHOW TABLES;" 2>/dev/null
        for tbl in account accounts user users player players tb_player; do
          _mysql "SELECT COUNT(*) FROM $tbl;" &>/dev/null 2>&1 && \
            _mysql "SELECT * FROM $tbl LIMIT 20;" && break
        done
        read -p "$(echo -e "${G}[Enter]...${N}")" _; exec </dev/tty ;;
      2)
        for tbl in character characters nro_character tb_character; do
          _mysql "SELECT COUNT(*) FROM $tbl;" &>/dev/null 2>&1 && \
            _mysql "SELECT * FROM $tbl LIMIT 20;" && break
        done
        read -p "$(echo -e "${G}[Enter]...${N}")" _; exec </dev/tty ;;
      3)
        _mysql "SHOW TABLES;" 2>/dev/null
        read -p "$(echo -e "${C}SQL: ${N}")" sql; exec </dev/tty
        [[ -n "$sql" ]] && _mysql "$sql"
        read -p "$(echo -e "${G}[Enter]...${N}")" _; exec </dev/tty ;;
      4)
        tail -50 "$HUNR_HOME/server.log" 2>/dev/null || err "Chưa có log"
        read -p "$(echo -e "${G}[Enter]...${N}")" _; exec </dev/tty ;;
      0) break ;;
    esac
  done
}

# ══════════════════════════════════════════════════════════════════
# MAIN MENU (sau khi setup xong)
# ══════════════════════════════════════════════════════════════════
main_menu() {
  while true; do
    banner
    # Hiển thị trạng thái nhanh
    if pgrep -f "\.jar" &>/dev/null 2>&1; then
      echo -e "  ${G}● Server: Đang chạy${N}"
    else
      echo -e "  ${R}● Server: Dừng${N}"
    fi
    echo ""
    echo -e "  ${Y}[1]${N} Start Server"
    echo -e "  ${Y}[2]${N} Stop Server"
    echo -e "  ${Y}[3]${N} Admin (DB, SQL)"
    echo -e "  ${Y}[4]${N} Patch lại APK"
    echo -e "  ${Y}[5]${N} Xem log server"
    echo -e "  ${Y}[6]${N} Kiểm tra kết nối"
    echo -e "  ${Y}[0]${N} Thoát"
    echo ""
    read -p "$(echo -e "${C}Chọn: ${N}")" ch; exec </dev/tty
    case "$ch" in
      1)
        bash "$HUNR_HOME/bin/start.sh"
        read -p $'\e[1;32m[Enter]...\e[0m' _; exec </dev/tty ;;
      2)
        bash "$HUNR_HOME/bin/stop.sh"
        read -p $'\e[1;32m[Enter]...\e[0m' _; exec </dev/tty ;;
      3) admin_menu ;;
      4)
        local apk_raw apk_pat
        apk_raw=$(step_get_apk)
        apk_pat=$(step_patch_apk "$apk_raw")
        step_sign_apk "$apk_pat"
        read -p $'\e[1;32m[Enter]...\e[0m' _; exec </dev/tty ;;
      5)
        tail -80 "$HUNR_HOME/server.log" 2>/dev/null || err "Chưa có log"
        read -p $'\e[1;32m[Enter]...\e[0m' _; exec </dev/tty ;;
      6)
        echo ""
        echo -e "${W}── Kết nối server ──${N}"
        for endpoint in "server.txt" "lists.txt"; do
          result=$(curl -s --max-time 3 "http://127.0.0.1:${HTTP_PORT}/$endpoint" 2>/dev/null)
          if [[ -n "$result" ]]; then
            echo -e "  ${G}● /$endpoint: $result${N}"
          else
            echo -e "  ${R}● /$endpoint: Không phản hồi${N}"
          fi
        done
        echo ""
        echo -e "${W}── Trạng thái ──${N}"
        mysqladmin -u root ping &>/dev/null && \
          echo -e "  ${G}● MariaDB: Chạy${N}" || echo -e "  ${R}● MariaDB: Dừng${N}"
        pgrep -f "\.jar" &>/dev/null && \
          echo -e "  ${G}● Spring Boot: Chạy (PID $(pgrep -f '\.jar' | head -1))${N}" || \
          echo -e "  ${R}● Spring Boot: Dừng${N}"
        [[ -f "$APK_OUT" ]] && \
          echo -e "  ${G}● APK: $(du -h "$APK_OUT" | cut -f1) – $APK_OUT${N}" || \
          echo -e "  ${Y}● APK: Chưa có – chạy [4] để patch${N}"
        echo ""
        read -p $'\e[1;32m[Enter]...\e[0m' _; exec </dev/tty ;;
      0) echo -e "${G}Bye!${N}"; exit 0 ;;
    esac
  done
}

# ══════════════════════════════════════════════════════════════════
# ENTRY POINT
# ══════════════════════════════════════════════════════════════════
banner

if [[ -f "$SETUP_FLAG" ]]; then
  main_menu
  exit 0
fi

# ─── FIRST RUN ────────────────────────────────────────────────────
echo -e "${W}  Lần đầu chạy – cài đặt tự động (6 bước)${N}"
echo ""
echo -e "  ${C}Bước 1:${N} Cài packages"
echo -e "  ${C}Bước 2:${N} Khởi động MariaDB"
echo -e "  ${C}Bước 3:${N} Tải + cấu hình HUNR Server (~1.1GB)"
echo -e "  ${C}Bước 4:${N} Lấy APK Android"
echo -e "  ${C}Bước 5:${N} Patch URL → 127.0.0.1:${HTTP_PORT}"
echo -e "  ${C}Bước 6:${N} Ký APK"
echo ""
echo -e "${Y}  ⚠ Bước 4 cần APK Android của Hồi Ức Ngọc Rồng.${N}"
echo -e "${Y}    Nếu chưa có: tải từ https://hoiucnro.com${N}"
echo -e "${Y}    hoặc apkpure.com rồi lưu vào /sdcard/Download/${N}"
echo ""
read -p "$(echo -e "${Y}  Nhấn Enter để bắt đầu...${N}")"
exec </dev/tty
echo ""

echo -e "${W}━━━ BƯỚC 1/6: Cài packages ━━━━━━━━━━━━━━━━━━━━━━━━━${N}"
step_packages

echo ""
echo -e "${W}━━━ BƯỚC 2/6: Khởi động MariaDB ━━━━━━━━━━━━━━━━━━━━${N}"
step_mariadb

echo ""
echo -e "${W}━━━ BƯỚC 3/6: Tải + cấu hình HUNR Server ━━━━━━━━━━━${N}"
step_server

echo ""
echo -e "${W}━━━ BƯỚC 4/6: Lấy APK Android ━━━━━━━━━━━━━━━━━━━━━${N}"
APK_RAW=$(step_get_apk)

echo ""
echo -e "${W}━━━ BƯỚC 5/6: Patch URL → localhost ━━━━━━━━━━━━━━━━${N}"
APK_PAT=$(step_patch_apk "$APK_RAW")

echo ""
echo -e "${W}━━━ BƯỚC 6/6: Ký APK ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${N}"
step_sign_apk "$APK_PAT"
_create_start_script

touch "$SETUP_FLAG"
echo "$(date)" > "$SETUP_FLAG"

echo ""
echo -e "${G}╔══════════════════════════════════════════════════════╗${N}"
echo -e "${G}║           CÀI ĐẶT HOÀN TẤT!  ✓                     ║${N}"
echo -e "${G}╚══════════════════════════════════════════════════════╝${N}"
echo ""
echo -e "  ${Y}APK game:${N}     $APK_OUT"
echo -e "  ${Y}Start server:${N} bash $HUNR_HOME/bin/start.sh"
echo -e "  ${Y}Menu:${N}         bash ~/hunr.sh"
echo ""
echo -e "${C}  Bước tiếp theo:${N}"
echo -e "  1. ${Y}bash $HUNR_HOME/bin/start.sh${N}"
echo -e "  2. Đợi ~15 giây Spring Boot khởi động"
echo -e "  3. Kiểm tra: ${Y}curl http://127.0.0.1:${HTTP_PORT}/server.txt${N}"
echo -e "     → Phải ra: ${G}Local:127.0.0.1:${GAME_PORT}:0,0,0${N}"
echo -e "  4. Gỡ HUNR cũ → cài ${Y}HUNR_Local.apk${N} từ Downloads"
echo -e "  5. Mở app → đăng nhập → chơi offline!"
echo ""
read -p "$(echo -e "${G}Nhấn Enter để vào menu chính...${N}")"
exec </dev/tty
main_menu
