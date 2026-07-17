#!/data/data/com.termux/files/usr/bin/bash
# ╔══════════════════════════════════════════════════════════════════╗
# ║   Hồi Ức Ngọc Rồng – Private Server Offline (Termux)           ║
# ║   Spring Boot + MariaDB + APK Mod Local sẵn                    ║
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
DRIVE_SERVER="1qQDKBYGRUxZma7Ax_8z1_v_s54_jAU09"     # Server ZIP ~1.1GB
DRIVE_APK_MOD="1UD_thIvP54w08ticP9LL6-Xi1EZKT24A"    # APK Mod Local (đã patch)

# DB
DB_NAME="hunr_2026"
DB_USER="root"
DB_PASS=""

# Ports
HTTP_PORT="1707"
GAME_PORT="14445"

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
      extracted_jar=$(find "/tmp/hunr_extract/" -path "*/target/*.jar" 2>/dev/null | head -1)
    fi

    if [[ -n "$extracted_jar" ]]; then
      cp "$extracted_jar" "$HUNR_HOME/"
      ok "JAR: $(basename $extracted_jar) → $HUNR_HOME/"
    else
      cp -r /tmp/hunr_extract/*/* "$HUNR_HOME/" 2>/dev/null || \
        cp -r /tmp/hunr_extract/* "$HUNR_HOME/"
      wrn "Không tìm thấy JAR rõ ràng – đã copy toàn bộ vào $HUNR_HOME/"
    fi

    rm -rf /tmp/HUNR_Server.zip /tmp/hunr_extract/ 2>/dev/null || true
  fi

  # ── Tạo static/lists.txt + server.txt (serve cả hai để APK Mod nào cũng khớp)
  local ADDR="Local:127.0.0.1:${GAME_PORT}:0,0,0"
  echo "$ADDR" > "$STATIC_DIR/lists.txt"
  echo "$ADDR" > "$STATIC_DIR/server.txt"
  ok "lists.txt + server.txt: $ADDR"

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

  mkdir -p "$HUNR_HOME/bin"
  _create_start_script
}

# ══════════════════════════════════════════════════════════════════
# Helper: Google Drive download
# ══════════════════════════════════════════════════════════════════
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
# BƯỚC 4: Tải APK Mod Local (đã patch offline)
# ══════════════════════════════════════════════════════════════════
step_apk() {
  echo ""
  echo -e "${W}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${N}"
  echo -e "${Y}  Tải APK Mod Local (đã patch kết nối localhost)${N}"
  echo -e "${W}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${N}"
  echo ""

  # Cấp quyền storage
  echo Y | termux-setup-storage 2>/dev/null || true
  sleep 1
  mkdir -p "$APK_DIR"

  if [[ -f "$APK_OUT" ]]; then
    local fsize
    fsize=$(stat -c%s "$APK_OUT" 2>/dev/null || echo 0)
    if [[ "$fsize" -gt 5000000 ]]; then
      ok "APK Mod Local đã có: $(du -h "$APK_OUT" | cut -f1)"
      return 0
    fi
  fi

  inf "Tải APK Mod Local từ Google Drive..."
  _gdrive_download "$DRIVE_APK_MOD" "$APK_OUT"

  local fsize
  fsize=$(stat -c%s "$APK_OUT" 2>/dev/null || echo 0)
  if [[ "$fsize" -lt 5000000 ]]; then
    rm -f "$APK_OUT"
    die "APK tải không thành công (${fsize} bytes). Thử lại hoặc tải thủ công."
  fi

  ok "APK Mod Local: $(du -h "$APK_OUT" | cut -f1)"
  ok "Đường dẫn: $APK_OUT"
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
  tries=0
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

  ok "Scripts OK: bash $HUNR_HOME/bin/start.sh"
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
    echo -e "  ${Y}[4]${N} Tải lại APK Mod Local"
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
        step_apk
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
        if [[ -f "$APK_OUT" ]]; then
          echo -e "  ${G}● APK: $(du -h "$APK_OUT" | cut -f1) – $APK_OUT${N}"
        else
          echo -e "  ${R}● APK: Chưa có – chạy [4] để tải${N}"
        fi
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
echo -e "${W}  ● Lần đầu chạy – cài đặt tự động (4 bước)${N}"
echo -e "${W}  ● Không cần thao tác thêm!${N}"
echo ""
echo -e "${C}  Bước 1: Cài packages${N}"
echo -e "${C}  Bước 2: Khởi động MariaDB${N}"
echo -e "${C}  Bước 3: Tải + cấu hình HUNR Server (~1.1GB)${N}"
echo -e "${C}  Bước 4: Tải APK Mod Local (đã patch offline)${N}"
echo ""
read -p "$(echo -e "${Y}  Nhấn Enter để bắt đầu...${N}")"
exec </dev/tty
echo ""

echo -e "${W}━━━ BƯỚC 1/4: Cài packages ━━━━━━━━━━━━━━━━━━━━━━━━━${N}"
step_packages

echo ""
echo -e "${W}━━━ BƯỚC 2/4: Khởi động MariaDB ━━━━━━━━━━━━━━━━━━━━${N}"
step_mariadb

echo ""
echo -e "${W}━━━ BƯỚC 3/4: Tải + cấu hình HUNR Server ━━━━━━━━━━━${N}"
step_server

echo ""
echo -e "${W}━━━ BƯỚC 4/4: Tải APK Mod Local ━━━━━━━━━━━━━━━━━━━━${N}"
step_apk

mkdir -p "$HUNR_HOME"
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
echo -e "  ${C}Bước tiếp theo:${N}"
echo -e "  1. Chạy: ${Y}bash $HUNR_HOME/bin/start.sh${N}"
echo -e "  2. Đợi ~15 giây (Spring Boot khởi động)"
echo -e "  3. Kiểm tra: ${Y}curl http://127.0.0.1:${HTTP_PORT}/lists.txt${N}"
echo -e "  4. Gỡ HUNR cũ → cài ${Y}HUNR_Local.apk${N} từ Downloads"
echo -e "  5. Mở app → đăng nhập → chơi offline!"
echo ""
read -p "$(echo -e "${G}Nhấn Enter để vào menu chính...${N}")"
exec </dev/tty
main_menu
