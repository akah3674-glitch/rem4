#!/data/data/com.termux/files/usr/bin/bash
# ╔══════════════════════════════════════════════════════════════════╗
# ║   Hồi Ức Ngọc Rồng – Private Server Offline (Termux)           ║
# ║   Spring Boot + MariaDB + APK patch tự động                    ║
# ║   Chạy: bash hunr_setup.sh                                      ║
# ╚══════════════════════════════════════════════════════════════════╝

set -euo pipefail

# ─── màu ──────────────────────────────────────────────────────────
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

# Google Drive IDs
DRIVE_SERVER="1qQDKBYGRUxZma7Ax_8z1_v_s54_jAU09"   # HUNR_Server.zip ~1.1GB

# DB
DB_NAME="hunr_2026"
DB_USER="root"
DB_PASS=""

# Ports
HTTP_PORT="1707"
GAME_PORT="14445"

# APK sign
KEYSTORE="$HOME/.hunr_sign.keystore"
KEY_ALIAS="hunrsign"
KEY_PASS="hunr12345"

# Tên APK gốc thường gặp
HUNR_PKG="com.hoiucnro.game"

# Patch string (phải đúng 31 byte mỗi bên)
OLD_URL="https://hoiucnro.com/server.txt"   # 31 bytes
NEW_URL="http://127.0.0.1:1707/lists.txt"   # 31 bytes

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

  inf "Cài packages cần thiết..."
  pkg install -y \
    curl wget python python-pip \
    openjdk-17 mariadb \
    openssl zip unzip \
    termux-tools 2>/dev/null | grep -E "^(Install|Unpacking|Setting)" || true

  inf "Cài pip packages..."
  pip install -q gdown requests 2>/dev/null || true

  ok "Packages OK"
}

# ══════════════════════════════════════════════════════════════════
# BƯỚC 2: Setup MariaDB
# ══════════════════════════════════════════════════════════════════
step_mariadb() {
  inf "Khởi tạo MariaDB..."
  mkdir -p "$HUNR_HOME"

  if [[ ! -d "$PREFIX/var/lib/mysql/mysql" ]]; then
    mysql_install_db --datadir="$PREFIX/var/lib/mysql" 2>/dev/null | tail -3 || true
    ok "MariaDB data dir đã tạo"
  else
    ok "MariaDB đã được khởi tạo trước đó"
  fi

  _start_mariadb

  inf "Tạo database '$DB_NAME'..."
  mysql -u root -e "
    CREATE DATABASE IF NOT EXISTS \`$DB_NAME\`
      CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
    GRANT ALL PRIVILEGES ON \`$DB_NAME\`.* TO 'root'@'localhost';
    FLUSH PRIVILEGES;
  " 2>/dev/null || wrn "DB có thể đã tồn tại"

  ok "Database '$DB_NAME' sẵn sàng"
}

_start_mariadb() {
  if mysqladmin -u root ping &>/dev/null 2>&1; then
    ok "MariaDB: đang chạy"; return 0
  fi
  inf "Khởi động MariaDB..."
  mysqladmin -u root shutdown 2>/dev/null || true
  sleep 1
  mysqld_safe \
    --datadir="$PREFIX/var/lib/mysql" \
    --socket="$PREFIX/tmp/mysql.sock" \
    --pid-file="$PREFIX/tmp/mysqld.pid" \
    --log-error="$PREFIX/tmp/mysqld.err" \
    --skip-networking=0 \
    --bind-address=127.0.0.1 \
    --port=3306 &>/dev/null &
  disown $! 2>/dev/null || true

  local tries=0
  while ! mysqladmin -u root ping &>/dev/null 2>&1; do
    sleep 1; tries=$((tries+1))
    [[ $tries -ge 25 ]] && die "MariaDB không khởi động! Log: $PREFIX/tmp/mysqld.err"
  done
  ok "MariaDB: Running"
}

# ══════════════════════════════════════════════════════════════════
# BƯỚC 3: Tải + setup HUNR Server
# ══════════════════════════════════════════════════════════════════
step_server() {
  mkdir -p "$HUNR_HOME" "$STATIC_DIR"

  # Kiểm tra JAR đã có chưa
  local jar
  jar=$(find "$HUNR_HOME" -maxdepth 2 -name "*.jar" 2>/dev/null | head -1)

  if [[ -n "$jar" ]]; then
    ok "Server JAR đã có: $(basename $jar)"
  else
    inf "Tải HUNR_Server.zip từ Google Drive (~1.1GB, có thể mất 5-15 phút)..."
    _gdrive_download "$DRIVE_SERVER" "/tmp/HUNR_Server.zip"

    local fsize
    fsize=$(stat -c%s "/tmp/HUNR_Server.zip" 2>/dev/null || echo 0)
    [[ "$fsize" -lt 1000000 ]] && die "HUNR_Server.zip không hợp lệ (${fsize} bytes)"

    inf "Giải nén server..."
    unzip -q "/tmp/HUNR_Server.zip" -d "/tmp/hunr_extract/" 2>/dev/null || \
      unzip "/tmp/HUNR_Server.zip" -d "/tmp/hunr_extract/"

    # Tìm JAR trong extract
    local extracted_jar
    extracted_jar=$(find "/tmp/hunr_extract/" -name "*.jar" -not -name "*sources*" -not -name "*javadoc*" 2>/dev/null | head -1)

    if [[ -z "$extracted_jar" ]]; then
      # Thử tìm trong target/
      extracted_jar=$(find "/tmp/hunr_extract/" -path "*/target/*.jar" 2>/dev/null | head -1)
    fi

    if [[ -n "$extracted_jar" ]]; then
      cp "$extracted_jar" "$HUNR_HOME/"
      ok "JAR: $(basename $extracted_jar) → $HUNR_HOME/"
    else
      # Copy toàn bộ nếu không tìm được JAR
      cp -r /tmp/hunr_extract/*/* "$HUNR_HOME/" 2>/dev/null || \
        cp -r /tmp/hunr_extract/* "$HUNR_HOME/"
      wrn "Không tìm thấy JAR rõ ràng – đã copy toàn bộ vào $HUNR_HOME/"
      wrn "Tìm file JAR thủ công: ls $HUNR_HOME/"
    fi

    rm -rf /tmp/HUNR_Server.zip /tmp/hunr_extract/ 2>/dev/null || true
  fi

  # ── Tạo static/lists.txt ──────────────────────────────────────
  echo "Local:127.0.0.1:${GAME_PORT}:0,0,0" > "$STATIC_DIR/lists.txt"
  ok "lists.txt: Local:127.0.0.1:${GAME_PORT}:0,0,0"

  # ── Tạo application.properties ───────────────────────────────
  cat > "$HUNR_HOME/application.properties" << APPEOF
# HUNR Private Server – Offline config
server.port=${HTTP_PORT}

# Database
spring.datasource.url=jdbc:mysql://127.0.0.1:3306/${DB_NAME}?useSSL=false&allowPublicKeyRetrieval=true&serverTimezone=Asia/Ho_Chi_Minh&characterEncoding=utf8mb4
spring.datasource.username=root
spring.datasource.password=
spring.datasource.driver-class-name=com.mysql.cj.jdbc.Driver

# JPA / Hibernate – tự tạo/update bảng
spring.jpa.hibernate.ddl-auto=update
spring.jpa.show-sql=false
spring.jpa.properties.hibernate.dialect=org.hibernate.dialect.MySQL8Dialect

# Serve static files (lists.txt)
spring.web.resources.static-locations=file:${HUNR_HOME}/static/,classpath:/static/
spring.mvc.static-path-pattern=/**

# Logging
logging.level.root=WARN
logging.level.com.hunr=INFO
APPEOF
  ok "application.properties đã tạo"

  # ── Tạo start script ─────────────────────────────────────────
  mkdir -p "$HUNR_HOME/bin"
  _create_start_script
}

_gdrive_download() {
  local drive_id="$1" out="$2"
  # Thử gdown trước
  if python3 -c "import gdown" &>/dev/null 2>&1; then
    python3 -c "
import gdown, sys
try:
    gdown.download(id='$drive_id', output='$out', quiet=False, fuzzy=True)
    print('OK')
except Exception as e:
    print(f'ERR:{e}'); sys.exit(1)
" && return 0
  fi
  # Fallback curl
  wrn "gdown không dùng được, thử curl..."
  local COOKIE="/tmp/gdcookie.txt"
  curl -sc "$COOKIE" "https://drive.google.com/uc?export=download&id=$drive_id" \
    -o /tmp/gd_check.html 2>/dev/null
  local CONFIRM
  CONFIRM=$(grep -oP '(?<=confirm=)[^&"]+' /tmp/gd_check.html 2>/dev/null | head -1)
  if [[ -n "$CONFIRM" ]]; then
    curl -Lb "$COOKIE" \
      "https://drive.google.com/uc?export=download&confirm=${CONFIRM}&id=$drive_id" \
      -o "$out" --progress-bar 2>&1 | tail -3
  else
    curl -L \
      "https://drive.google.com/uc?export=download&id=$drive_id&confirm=t&uuid=$(date +%s)" \
      -o "$out" --progress-bar 2>&1 | tail -3
  fi
}

# ══════════════════════════════════════════════════════════════════
# BƯỚC 4: Lấy APK gốc
# ══════════════════════════════════════════════════════════════════
step_get_apk() {
  echo ""
  echo -e "${W}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${N}"
  echo -e "${Y}  Cần APK gốc của Hồi Ức Ngọc Rồng để patch offline${N}"
  echo -e "${W}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${N}"
  echo ""
  echo -e "  ${C}[1]${N} Tự động lấy APK từ app đã cài (nếu đã cài Hồi Ức Ngọc Rồng)"
  echo -e "  ${C}[2]${N} Nhập đường dẫn file APK thủ công"
  echo ""
  read -p "$(echo -e "${C}Chọn [1/2]: ${N}")" apk_choice
  exec </dev/tty

  local apk_raw="/tmp/hunr_original.apk"

  case "$apk_choice" in
    1)
      inf "Tìm APK đã cài..."
      local apk_path
      apk_path=$(pm path "$HUNR_PKG" 2>/dev/null | sed 's/package://' | tr -d '[:space:]') || true
      if [[ -z "$apk_path" ]]; then
        # Thử tên package khác
        for pkg in com.hoiucnro com.hunr.game vn.hoiucnro.game; do
          apk_path=$(pm path "$pkg" 2>/dev/null | sed 's/package://' | tr -d '[:space:]') || true
          [[ -n "$apk_path" ]] && break
        done
      fi
      if [[ -n "$apk_path" && -f "$apk_path" ]]; then
        cp "$apk_path" "$apk_raw"
        ok "Lấy APK từ: $apk_path"
      else
        echo ""
        err "Không tìm thấy app cài sẵn!"
        echo -e "  ${Y}Cách lấy APK thủ công:${N}"
        echo -e "  1. Tải APK từ https://hoiucnro.com"
        echo -e "  2. Copy vào Downloads: /sdcard/Download/hunr.apk"
        echo -e "  3. Chạy lại script và chọn [2]"
        echo ""
        read -p "$(echo -e "${Y}Nhấn Enter để thoát và tải APK trước...${N}")" _
        exec </dev/tty
        exit 1
      fi
      ;;
    2)
      echo ""
      echo -e "  ${C}Ví dụ: /sdcard/Download/HoiUcNgocRong.apk${N}"
      read -p "$(echo -e "${C}Đường dẫn APK: ${N}")" user_apk
      exec </dev/tty
      user_apk="${user_apk/#\~/$HOME}"
      [[ ! -f "$user_apk" ]] && die "Không tìm thấy file: $user_apk"
      cp "$user_apk" "$apk_raw"
      ok "APK gốc: $(du -h "$apk_raw" | cut -f1)"
      ;;
    *)
      die "Chọn không hợp lệ"
      ;;
  esac

  # Kiểm tra file
  local fsize
  fsize=$(stat -c%s "$apk_raw" 2>/dev/null || echo 0)
  [[ "$fsize" -lt 500000 ]] && die "APK có vẻ không hợp lệ (${fsize} bytes)"
  echo "$apk_raw"
}

# ══════════════════════════════════════════════════════════════════
# BƯỚC 5: Patch APK (thay URL server.txt → localhost)
# ══════════════════════════════════════════════════════════════════
step_patch_apk() {
  local apk_in="$1"
  local apk_out="/tmp/hunr_patched.apk"

  inf "Patch URL server list: hoiucnro.com → 127.0.0.1:${HTTP_PORT} ..."

  python3 << PYEOF
import sys, zipfile, os

apk_in  = "$apk_in"
apk_out = "$apk_out"

# Đúng 31 byte mỗi bên – không cần pad
OLD = b"https://hoiucnro.com/server.txt"   # 31 bytes
NEW = b"http://127.0.0.1:${HTTP_PORT}/lists.txt"  # 31 bytes

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
        print("[✗] Không tìm thấy global-metadata.dat!")
        sys.exit(1)
    print(f"  [i] Metadata: {meta_path}")
    data = zin.read(meta_path)

print(f"  [i] Size: {len(data):,} bytes")

if OLD not in data:
    print(f"  [!] Không tìm thấy URL cũ: {OLD.decode()}")
    print(f"  [!] APK này có thể đã patch hoặc khác phiên bản")
    # Vẫn ghi ra để thử
    patched = data
    ok_flag = False
else:
    patched = data.replace(OLD, NEW)
    count = data.count(OLD)
    print(f"  [✓] Đã thay {count} lần: {OLD.decode()} → {NEW.decode()}")
    ok_flag = True

# Ghi APK mới
with zipfile.ZipFile(apk_in, 'r') as zin, \
     zipfile.ZipFile(apk_out, 'w', zipfile.ZIP_DEFLATED, compresslevel=6) as zout:
    for item in zin.infolist():
        raw = zin.read(item.filename)
        if item.filename == meta_path:
            zout.writestr(item, patched)
        else:
            zout.writestr(item, raw)

print(f"[✓] Patch xong → {apk_out}")
if not ok_flag:
    print("[!] CẢNH BÁO: URL không thay được – game có thể vẫn kết nối online")
PYEOF

  [[ ! -f "$apk_out" ]] && die "Patch APK thất bại!"
  ok "Patch xong"
  echo "$apk_out"
}

# ══════════════════════════════════════════════════════════════════
# BƯỚC 6: Ký APK
# ══════════════════════════════════════════════════════════════════
step_sign_apk() {
  local apk_in="$1"

  if [[ ! -f "$KEYSTORE" ]]; then
    inf "Tạo keystore..."
    keytool -genkeypair -v \
      -keystore "$KEYSTORE" \
      -alias "$KEY_ALIAS" \
      -keyalg RSA -keysize 2048 -validity 9999 \
      -dname "CN=HUNR Local,O=HUNR,C=VN" \
      -storepass "$KEY_PASS" -keypass "$KEY_PASS" \
      2>/dev/null && ok "Keystore OK" || wrn "Keystore lỗi nhỏ (bỏ qua)"
  fi

  inf "Ký APK..."
  jarsigner \
    -keystore "$KEYSTORE" \
    -storepass "$KEY_PASS" -keypass "$KEY_PASS" \
    -digestalg SHA-256 -sigalg SHA256withRSA \
    "$apk_in" "$KEY_ALIAS" 2>/dev/null && ok "Ký APK OK" || wrn "jarsigner lỗi nhỏ"

  termux-setup-storage 2>/dev/null || true
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

# Khởi động MariaDB
if ! mysqladmin -u root ping &>/dev/null 2>&1; then
  inf "Khởi động MariaDB..."
  mysqld_safe \
    --datadir="\$PREFIX/var/lib/mysql" \
    --socket="\$PREFIX/tmp/mysql.sock" \
    --pid-file="\$PREFIX/tmp/mysqld.pid" \
    --skip-networking=0 --bind-address=127.0.0.1 --port=3306 &>/dev/null &
  disown
  local tries=0
  while ! mysqladmin -u root ping &>/dev/null 2>&1; do
    sleep 1; tries=\$((tries+1))
    [[ \$tries -ge 20 ]] && { echo "[✗] MariaDB không chạy!"; exit 1; }
  done
fi
ok "MariaDB: Running"

# Tìm JAR
JAR=\$(find "\$HUNR_HOME" -maxdepth 2 -name "*.jar" -not -name "*sources*" 2>/dev/null | head -1)
if [[ -z "\$JAR" ]]; then
  err "Không tìm thấy JAR trong \$HUNR_HOME!"
  echo "  → Kiểm tra: ls \$HUNR_HOME"
  exit 1
fi

inf "Khởi động HUNR Server: \$(basename \$JAR)"
inf "  HTTP: 127.0.0.1:\${HTTP_PORT}"
inf "  Game: 127.0.0.1:\${GAME_PORT}"
echo ""

# Chạy Spring Boot với application.properties local
cd "\$HUNR_HOME"
java -jar "\$JAR" \
  --spring.config.location="file:\${HUNR_HOME}/application.properties" \
  2>&1 | tee "\$HUNR_HOME/server.log" &
JAVA_PID=\$!
disown \$JAVA_PID 2>/dev/null || true

echo ""
ok "Server đã khởi động (PID \$JAVA_PID)"
ok "Đợi ~15 giây rồi mở HUNR_Local.apk"
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

  # Shortcut ở HOME
  cat > "$HOME/hunr.sh" << SHORTEOF
#!/data/data/com.termux/files/usr/bin/bash
exec bash "$HUNR_HOME/hunr_setup.sh" "\$@"
SHORTEOF
  chmod +x "$HOME/hunr.sh"

  ok "Launcher OK: bash $HUNR_HOME/bin/start.sh"
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
    if mysqladmin -u root ping &>/dev/null 2>&1; then
      echo -e "  ${G}● DB: Online (${DB_NAME})${N}"
    else
      echo -e "  ${R}● DB: Offline${N}"
    fi
    echo ""
    echo -e "  ${Y}[1]${N} Xem danh sách tài khoản"
    echo -e "  ${Y}[2]${N} Xem nhân vật"
    echo -e "  ${Y}[3]${N} Chạy SQL tuỳ ý"
    echo -e "  ${Y}[4]${N} Xem log server"
    echo -e "  ${Y}[0]${N} Quay lại"
    echo ""
    read -p "$(echo -e "${C}Chọn: ${N}")" ch
    exec </dev/tty
    case "$ch" in
      1)
        echo ""
        _mysql "SHOW TABLES;" 2>/dev/null
        echo ""
        # Thử nhiều tên bảng có thể có
        for tbl in account accounts user users player players tb_player; do
          if _mysql "SELECT COUNT(*) FROM $tbl;" &>/dev/null 2>&1; then
            echo -e "${C}Bảng $tbl:${N}"
            _mysql "SELECT * FROM $tbl LIMIT 20;" 2>/dev/null
            break
          fi
        done
        read -p "$(echo -e "${G}[Enter]...${N}")" _
        exec </dev/tty
        ;;
      2)
        echo ""
        for tbl in character characters nro_character player_character tb_character; do
          if _mysql "SELECT COUNT(*) FROM $tbl;" &>/dev/null 2>&1; then
            echo -e "${C}Bảng $tbl:${N}"
            _mysql "SELECT * FROM $tbl LIMIT 20;" 2>/dev/null
            break
          fi
        done
        read -p "$(echo -e "${G}[Enter]...${N}")" _
        exec </dev/tty
        ;;
      3)
        echo ""
        echo -e "${C}Tables hiện có:${N}"
        _mysql "SHOW TABLES;" 2>/dev/null
        echo ""
        read -p "$(echo -e "${C}SQL: ${N}")" sql
        exec </dev/tty
        [[ -n "$sql" ]] && _mysql "$sql"
        read -p "$(echo -e "${G}[Enter]...${N}")" _
        exec </dev/tty
        ;;
      4)
        echo ""
        tail -50 "$HUNR_HOME/server.log" 2>/dev/null || err "Chưa có log"
        read -p "$(echo -e "${G}[Enter]...${N}")" _
        exec </dev/tty
        ;;
      0) break ;;
    esac
  done
}

# ══════════════════════════════════════════════════════════════════
# MAIN MENU
# ══════════════════════════════════════════════════════════════════
main_menu() {
  while true; do
    banner
    echo -e "  ${Y}[1]${N} Start Server"
    echo -e "  ${Y}[2]${N} Stop Server"
    echo -e "  ${Y}[3]${N} Admin (xem DB, SQL...)"
    echo -e "  ${Y}[4]${N} Patch lại APK"
    echo -e "  ${Y}[5]${N} Xem log server"
    echo -e "  ${Y}[6]${N} Kiểm tra trạng thái"
    echo -e "  ${Y}[0]${N} Thoát"
    echo ""
    read -p "$(echo -e "${C}Chọn: ${N}")" ch
    exec </dev/tty
    case "$ch" in
      1)
        bash "$HUNR_HOME/bin/start.sh"
        read -p $'\e[1;32m[Enter]...\e[0m' _
        exec </dev/tty
        ;;
      2)
        bash "$HUNR_HOME/bin/stop.sh"
        read -p $'\e[1;32m[Enter]...\e[0m' _
        exec </dev/tty
        ;;
      3) admin_menu ;;
      4)
        inf "Patch lại APK..."
        local apk_raw apk_pat
        apk_raw=$(step_get_apk)
        apk_pat=$(step_patch_apk "$apk_raw")
        step_sign_apk "$apk_pat"
        read -p $'\e[1;32m[Enter]...\e[0m' _
        exec </dev/tty
        ;;
      5)
        echo ""
        tail -80 "$HUNR_HOME/server.log" 2>/dev/null || err "Chưa có log"
        read -p $'\e[1;32m[Enter]...\e[0m' _
        exec </dev/tty
        ;;
      6)
        echo ""
        echo -e "${W}── Trạng thái hệ thống ──${N}"
        if mysqladmin -u root ping &>/dev/null 2>&1; then
          echo -e "  ${G}● MariaDB: Đang chạy${N}"
        else
          echo -e "  ${R}● MariaDB: Dừng${N}"
        fi
        if pgrep -f "\.jar" &>/dev/null 2>&1; then
          local pid
          pid=$(pgrep -f "\.jar" | head -1)
          echo -e "  ${G}● Spring Boot: Đang chạy (PID $pid)${N}"
        else
          echo -e "  ${R}● Spring Boot: Dừng${N}"
        fi
        if curl -s "http://127.0.0.1:${HTTP_PORT}/lists.txt" &>/dev/null 2>&1; then
          echo -e "  ${G}● HTTP (:${HTTP_PORT}/lists.txt): OK${N}"
        else
          echo -e "  ${Y}● HTTP (:${HTTP_PORT}/lists.txt): Chưa sẵn sàng${N}"
        fi
        echo ""
        echo -e "  ${C}APK: $APK_OUT${N}"
        echo -e "  ${C}JAR: $(find $HUNR_HOME -name '*.jar' 2>/dev/null | head -1 || echo 'chưa có')${N}"
        echo ""
        read -p $'\e[1;32m[Enter]...\e[0m' _
        exec </dev/tty
        ;;
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
echo -e "${W}  ● Lần đầu chạy – cài đặt tự động${N}"
echo -e "${W}  ● KHÔNG cần thao tác (trừ cung cấp APK)${N}"
echo ""
echo -e "${C}  Gồm 6 bước. APK sẽ được hỏi ở bước 4.${N}"
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
echo -e "${W}━━━ BƯỚC 4/6: Lấy APK gốc ━━━━━━━━━━━━━━━━━━━━━━━━━${N}"
APK_RAW=$(step_get_apk)

echo ""
echo -e "${W}━━━ BƯỚC 5/6: Patch APK → localhost ━━━━━━━━━━━━━━━━${N}"
APK_PAT=$(step_patch_apk "$APK_RAW")

echo ""
echo -e "${W}━━━ BƯỚC 6/6: Ký APK ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${N}"
step_sign_apk "$APK_PAT"
_create_start_script

mkdir -p "$HUNR_HOME"
touch "$SETUP_FLAG"
echo "$(date)" > "$SETUP_FLAG"

echo ""
echo -e "${G}╔══════════════════════════════════════════════════════╗${N}"
echo -e "${G}║           CÀI ĐẶT HOÀN TẤT!                         ║${N}"
echo -e "${G}╚══════════════════════════════════════════════════════╝${N}"
echo ""
echo -e "  ${Y}APK game:${N}     $APK_OUT"
echo -e "  ${Y}Start server:${N} bash $HUNR_HOME/bin/start.sh"
echo -e "  ${Y}Menu:${N}         bash ~/hunr.sh"
echo ""
echo -e "  ${C}Bước tiếp theo:${N}"
echo -e "  1. Chạy: ${Y}bash $HUNR_HOME/bin/start.sh${N}"
echo -e "  2. Đợi ~15 giây (Spring Boot khởi động)"
echo -e "  3. Kiểm tra: ${Y}curl http://127.0.0.1:${HTTP_PORT}/lists.txt${N}"
echo -e "  4. Gỡ HUNR cũ → cài APK từ Downloads → ${Y}HUNR_Local.apk${N}"
echo -e "  5. Đăng nhập → chơi offline!"
echo ""
read -p "$(echo -e "${G}Nhấn Enter để vào menu chính...${N}")"
exec </dev/tty
main_menu
