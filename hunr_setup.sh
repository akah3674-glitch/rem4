#!/data/data/com.termux/files/usr/bin/bash
# ╔══════════════════════════════════════════════════════════════════╗
# ║   Hồi Ức Ngọc Rồng – Termux Auto Setup                        ║
# ║   Nguồn: Google Drive ZIP (Server Spring Boot + Resources)     ║
# ║   Chạy: bash hunr_setup.sh                                     ║
# ╚══════════════════════════════════════════════════════════════════╝

R='\033[1;31m' G='\033[1;32m' Y='\033[1;33m'
B='\033[1;34m' C='\033[1;36m' W='\033[1;37m' N='\033[0m'
ok()  { echo -e "${G}[✓]${N} $*"; }
err() { echo -e "${R}[✗]${N} $*"; }
inf() { echo -e "${B}[i]${N} $*"; }
wrn() { echo -e "${Y}[!]${N} $*"; }

# ─── Config ───────────────────────────────────────────────────────
HUNR_HOME="$HOME/hunr-server"
GDRIVE_SERVER="1qQDKBYGRUxZma7Ax_8z1_v_s54_jAU09"
GDRIVE_CLIENT="11W9nK8XA1209D1nzi2D7tGzxpM5X9a4t"
DB_NAME="hunr_2026"
ZIP_TMP="/tmp/hunr_server.zip"
SETUP_FLAG="$HUNR_HOME/.setup_done"
JAR_NAME="HunrProvision-0.0.1-SNAPSHOT.jar"

banner() {
  clear
  echo -e "${C}"
  echo "  ██╗  ██╗██╗   ██╗███╗   ██╗██████╗ "
  echo "  ██║  ██║██║   ██║████╗  ██║██╔══██╗"
  echo "  ███████║██║   ██║██╔██╗ ██║██████╔╝"
  echo "  ██╔══██║██║   ██║██║╚██╗██║██╔══██╗"
  echo "  ██║  ██║╚██████╔╝██║ ╚████║██║  ██║"
  echo "  ╚═╝  ╚═╝ ╚═════╝ ╚═╝  ╚═══╝╚═╝  ╚═╝"
  echo -e "${Y}     Hồi Ức Ngọc Rồng – Private Server${N}"
  echo -e "${G}  ════════════════════════════════════════${N}"
  echo ""
}

# ══════════════════════════════════════════════════════════════════
# BƯỚC 1 – Cài Packages
# ══════════════════════════════════════════════════════════════════
step_packages() {
  inf "Cập nhật pkg..."
  pkg update -y 2>/dev/null | tail -1 || true

  inf "Cài packages (openjdk-17, mariadb, unzip, curl, wget)..."
  pkg install -y curl wget openjdk-17 mariadb unzip openssl python 2>&1 \
    | grep "^Setting up" || true

  ok "Packages xong!"
}

# ══════════════════════════════════════════════════════════════════
# BƯỚC 2 – Tải Server ZIP từ Google Drive
# ══════════════════════════════════════════════════════════════════
step_download_zip() {
  local DRIVE_URL="https://drive.usercontent.google.com/download?id=${GDRIVE_SERVER}&export=download&authuser=0&confirm=t"

  if [[ -f "$ZIP_TMP" ]]; then
    local sz; sz=$(stat -c%s "$ZIP_TMP" 2>/dev/null || echo 0)
    if [[ "$sz" -gt 1000000000 ]]; then
      ok "ZIP đã có sẵn ($(du -h "$ZIP_TMP" | cut -f1)) – bỏ qua tải"
      return 0
    fi
    wrn "ZIP chưa đầy đủ ($sz bytes) – tải lại..."
    rm -f "$ZIP_TMP"
  fi

  inf "Tải HUNR_Server.zip từ Google Drive (~1.1GB)..."
  curl -L -A "Mozilla/5.0" \
    --retry 5 --retry-delay 10 \
    --continue-at - \
    --progress-bar \
    "$DRIVE_URL" \
    -o "$ZIP_TMP" || true

  local sz; sz=$(stat -c%s "$ZIP_TMP" 2>/dev/null || echo 0)
  if [[ "$sz" -lt 500000000 ]]; then
    wrn "curl chưa đủ ($sz bytes), thử wget..."
    wget -c --show-progress -q "$DRIVE_URL" -O "$ZIP_TMP" || true
    sz=$(stat -c%s "$ZIP_TMP" 2>/dev/null || echo 0)
  fi

  if [[ "$sz" -lt 500000000 ]]; then
    err "Tải thất bại! Kích thước: $sz bytes"
    err "Thử tải thủ công và đặt vào: $ZIP_TMP"
    return 1
  fi

  ok "Tải xong! Size: $(du -h "$ZIP_TMP" | cut -f1)"
}

# ══════════════════════════════════════════════════════════════════
# BƯỚC 3 – Giải nén và setup thư mục server
# ══════════════════════════════════════════════════════════════════
step_extract() {
  local TMP_DIR="/tmp/hunr_src"

  if [[ -d "$HUNR_HOME" && -f "$HUNR_HOME/$JAR_NAME" ]]; then
    ok "Server đã được extract trước đó – bỏ qua"
    return 0
  fi

  inf "Giải nén HUNR_Server.zip..."
  rm -rf "$TMP_DIR"
  mkdir -p "$TMP_DIR"
  unzip -q "$ZIP_TMP" -d "$TMP_DIR" 2>/dev/null || {
    err "Giải nén thất bại!"
    return 1
  }

  # Tìm thư mục Hunr2026
  local SRC
  SRC=$(find "$TMP_DIR" -maxdepth 2 -name "HunrProvision-0.0.1-SNAPSHOT.jar" | head -1)
  if [[ -z "$SRC" ]]; then
    err "Không tìm thấy JAR trong ZIP!"
    ls -la "$TMP_DIR"
    return 1
  fi
  local SRC_DIR; SRC_DIR=$(dirname "$(dirname "$SRC")")

  inf "Copying server files to $HUNR_HOME ..."
  mkdir -p "$HUNR_HOME"
  # Copy JAR
  cp "$SRC" "$HUNR_HOME/$JAR_NAME"
  # Copy thư mục resources và Config (cần thiết khi chạy)
  [[ -d "$SRC_DIR/resources" ]] && cp -r "$SRC_DIR/resources" "$HUNR_HOME/"
  [[ -d "$SRC_DIR/Config" ]]    && cp -r "$SRC_DIR/Config"    "$HUNR_HOME/"
  [[ -d "$SRC_DIR/data" ]]      && cp -r "$SRC_DIR/data"      "$HUNR_HOME/"
  [[ -d "$SRC_DIR/sql" ]]       && cp -r "$SRC_DIR/sql"       "$HUNR_HOME/"
  mkdir -p "$HUNR_HOME/logs"

  ok "Extract xong! JAR: $HUNR_HOME/$JAR_NAME ($(du -h "$HUNR_HOME/$JAR_NAME" | cut -f1))"
  # Dọn tmp
  rm -rf "$TMP_DIR"
}

# ══════════════════════════════════════════════════════════════════
# BƯỚC 4 – Cấu hình application.properties
# ══════════════════════════════════════════════════════════════════
step_config() {
  local PROPS="$HUNR_HOME/application.properties"

  inf "Tạo application.properties..."
  cat > "$PROPS" << 'EOF'
############################################################
# SERVER / GAME SETTINGS
############################################################
server.id=1
server.name=HUNR Local
server.port_game=14445
server.host=127.0.0.1
server.redirect=false
server.autosave.delay=300000
game.data.version=1
game.item.version=1
game.map.version=4
game.skill.version=1
game.servers=Local:127.0.0.1:14445:0,0,0
game.exp=5
game.item.quantity.max=1000000
game.log_ccu=1
game.bot_token=
game.chat_id=0
############################################################
# DATABASE
############################################################
database.port=3306
database.host=localhost
database.name=hunr_2026
database.user=root
database.password=
spring.datasource.url=jdbc:mysql://localhost:3306/hunr_2026?useUnicode=true&characterEncoding=utf8&rewriteBatchedStatements=true&serverTimezone=Asia/Bangkok
spring.datasource.username=root
spring.datasource.password=
spring.datasource.hikari.pool-name=GamePool
spring.datasource.hikari.maximum-pool-size=32
spring.datasource.hikari.minimum-idle=8
spring.datasource.hikari.connection-timeout=30000
spring.datasource.hikari.idle-timeout=600000
spring.datasource.hikari.max-lifetime=1800000
############################################################
# SPRING BOOT PORT (admin/API)
############################################################
server.port=1707
############################################################
# JPA / HIBERNATE
############################################################
spring.jpa.show-sql=false
spring.jpa.open-in-view=false
spring.jpa.hibernate.ddl-auto=update
spring.jpa.properties.hibernate.dialect=org.hibernate.dialect.MySQL8Dialect
spring.jpa.properties.hibernate.jdbc.batch_size=50
spring.jpa.properties.hibernate.order_inserts=true
spring.jpa.properties.hibernate.order_updates=true
############################################################
# SPRING SECURITY
############################################################
spring.security.user.name=admin
spring.security.user.password=hunr2026
############################################################
# ACTUATOR & LOGGING
############################################################
management.endpoints.web.exposure.include=health,metrics
management.endpoint.health.show-details=never
logging.level.com.zaxxer.hikari=INFO
logging.level.org.hibernate.SQL=ERROR
EOF

  ok "application.properties đã tạo"
}

# ══════════════════════════════════════════════════════════════════
# BƯỚC 5 – Setup MariaDB
# ══════════════════════════════════════════════════════════════════
step_mariadb() {
  inf "Khởi động MariaDB..."
  mkdir -p "$PREFIX/var/lib/mysql"

  # Init nếu chưa có
  if [[ ! -d "$PREFIX/var/lib/mysql/mysql" ]]; then
    inf "Khởi tạo MariaDB lần đầu..."
    mysql_install_db --datadir="$PREFIX/var/lib/mysql" 2>/dev/null | tail -3 || true
  fi

  # Start MariaDB
  mysqld_safe --datadir="$PREFIX/var/lib/mysql" \
    --socket="$PREFIX/tmp/mysql.sock" \
    --port=3306 \
    --user="$(whoami)" \
    --skip-networking=false \
    --bind-address=127.0.0.1 \
    --log-error="$HOME/mariadb.log" &
  local MARIA_PID=$!

  inf "Chờ MariaDB khởi động (15s)..."
  sleep 15

  # Kiểm tra MariaDB
  local TRIES=0
  while ! mysql -u root --socket="$PREFIX/tmp/mysql.sock" -e "SELECT 1" &>/dev/null; do
    sleep 3
    TRIES=$((TRIES+1))
    if [[ $TRIES -ge 10 ]]; then
      err "MariaDB không khởi động được! Xem log: $HOME/mariadb.log"
      return 1
    fi
  done
  ok "MariaDB đã chạy!"

  # Tạo database
  inf "Tạo database $DB_NAME ..."
  mysql -u root --socket="$PREFIX/tmp/mysql.sock" << EOF
CREATE DATABASE IF NOT EXISTS \`${DB_NAME}\` CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
GRANT ALL PRIVILEGES ON \`${DB_NAME}\`.* TO 'root'@'localhost';
FLUSH PRIVILEGES;
EOF
  ok "Database $DB_NAME đã tạo!"

  # Import SQL phụ nếu có
  if [[ -f "$HUNR_HOME/sql/bo_mong_setup.sql" ]]; then
    inf "Import bo_mong_setup.sql..."
    mysql -u root --socket="$PREFIX/tmp/mysql.sock" "$DB_NAME" < "$HUNR_HOME/sql/bo_mong_setup.sql" 2>/dev/null || true
    ok "Import SQL phụ xong"
  fi
}

# ══════════════════════════════════════════════════════════════════
# BƯỚC 6 – Tạo start/stop scripts
# ══════════════════════════════════════════════════════════════════
step_scripts() {
  # start.sh
  cat > "$HUNR_HOME/start.sh" << SCRIPT
#!/data/data/com.termux/files/usr/bin/bash
cd "$HUNR_HOME"
echo "[*] Đảm bảo MariaDB đang chạy..."
if ! mysql -u root --socket="\$PREFIX/tmp/mysql.sock" -e "SELECT 1" &>/dev/null 2>&1; then
  mysqld_safe --datadir="\$PREFIX/var/lib/mysql" \\
    --socket="\$PREFIX/tmp/mysql.sock" --port=3306 \\
    --skip-networking=false --bind-address=127.0.0.1 \\
    --log-error="\$HOME/mariadb.log" &
  sleep 10
fi
echo "[*] Khởi động HUNR Game Server (port 14445)..."
java -Xms512m -Xmx2g \\
  -Dfile.encoding=UTF-8 \\
  -Dspring.config.location="$HUNR_HOME/application.properties" \\
  -jar "$HUNR_HOME/$JAR_NAME" 2>&1 | tee -a "$HUNR_HOME/logs/server.log"
SCRIPT

  # stop.sh
  cat > "$HUNR_HOME/stop.sh" << 'SCRIPT'
#!/data/data/com.termux/files/usr/bin/bash
echo "[*] Dừng HUNR server..."
pkill -f "HunrProvision" || true
sleep 2
echo "[*] Dừng MariaDB..."
mysqladmin -u root --socket="$PREFIX/tmp/mysql.sock" shutdown 2>/dev/null || pkill mysqld || true
echo "[✓] Đã dừng tất cả"
SCRIPT

  chmod +x "$HUNR_HOME/start.sh" "$HUNR_HOME/stop.sh"
  ok "start.sh và stop.sh đã tạo"
}

# ══════════════════════════════════════════════════════════════════
# MENU CHÍNH
# ══════════════════════════════════════════════════════════════════
menu() {
  banner
  echo -e "  ${W}1.${N} Setup lần đầu (tải + cài đặt hoàn toàn)"
  echo -e "  ${W}2.${N} Khởi động server"
  echo -e "  ${W}3.${N} Dừng server"
  echo -e "  ${W}4.${N} Xem log server"
  echo -e "  ${W}5.${N} Vào MySQL shell"
  echo -e "  ${W}6.${N} Thông tin server"
  echo -e "  ${W}0.${N} Thoát"
  echo ""
  echo -ne "  ${C}Chọn [0-6]:${N} "
  read -r choice

  case "$choice" in
    1) do_setup ;;
    2) do_start ;;
    3) do_stop ;;
    4) do_log ;;
    5) do_mysql ;;
    6) do_info ;;
    0) exit 0 ;;
    *) echo -e "${R}Lựa chọn không hợp lệ!${N}"; sleep 1; menu ;;
  esac
}

do_setup() {
  banner
  echo -e "${Y}=== BẮT ĐẦU SETUP HUNR SERVER ===${N}"
  echo ""
  step_packages
  echo ""
  step_download_zip || { err "Tải thất bại!"; read -r; menu; return; }
  echo ""
  step_extract || { err "Extract thất bại!"; read -r; menu; return; }
  echo ""
  step_config
  echo ""
  step_mariadb || { err "MariaDB thất bại!"; read -r; menu; return; }
  echo ""
  step_scripts
  echo ""
  touch "$SETUP_FLAG"
  echo -e "${G}════════════════════════════════════════${N}"
  echo -e "${G}[✓] SETUP HOÀN TẤT!${N}"
  echo -e "${Y}Game port:  14445${N}"
  echo -e "${Y}Admin port: 1707${N}"
  echo -e "${Y}Database:   $DB_NAME${N}"
  echo -e "${G}════════════════════════════════════════${N}"
  echo ""
  echo -ne "Khởi động server ngay? [y/n]: "
  read -r ans
  [[ "$ans" == "y" || "$ans" == "Y" ]] && do_start
  menu
}

do_start() {
  banner
  if [[ ! -f "$HUNR_HOME/$JAR_NAME" ]]; then
    err "Server chưa được setup! Chọn Menu 1 trước."
    sleep 2; menu; return
  fi
  inf "Khởi động HUNR Server..."
  bash "$HUNR_HOME/start.sh"
}

do_stop() {
  bash "$HUNR_HOME/stop.sh"
  echo ""
  read -rp "Nhấn Enter để về menu..." _
  menu
}

do_log() {
  local LOG="$HUNR_HOME/logs/server.log"
  if [[ -f "$LOG" ]]; then
    tail -50 "$LOG"
  else
    err "Chưa có log! Server chưa được khởi động."
  fi
  echo ""
  read -rp "Nhấn Enter để về menu..." _
  menu
}

do_mysql() {
  inf "Mở MySQL shell (database: $DB_NAME)..."
  mysql -u root --socket="$PREFIX/tmp/mysql.sock" "$DB_NAME"
  menu
}

do_info() {
  banner
  echo -e "${C}=== THÔNG TIN SERVER ===${N}"
  echo -e "${W}Home:${N}       $HUNR_HOME"
  echo -e "${W}JAR:${N}        $JAR_NAME"
  echo -e "${W}Game port:${N}  14445"
  echo -e "${W}Admin port:${N} 1707"
  echo -e "${W}Database:${N}   $DB_NAME"
  echo -e "${W}Log:${N}        $HUNR_HOME/logs/server.log"
  echo ""
  # Check status
  if pgrep -f "HunrProvision" > /dev/null; then
    echo -e "${G}[✓] Server đang chạy${N}"
  else
    echo -e "${R}[✗] Server đang dừng${N}"
  fi
  if mysql -u root --socket="$PREFIX/tmp/mysql.sock" -e "SELECT 1" &>/dev/null 2>&1; then
    echo -e "${G}[✓] MariaDB đang chạy${N}"
  else
    echo -e "${R}[✗] MariaDB đang dừng${N}"
  fi
  echo ""
  read -rp "Nhấn Enter để về menu..." _
  menu
}

# ── Entry point ─────────────────────────────────────────────────
if [[ -f "$SETUP_FLAG" ]]; then
  menu
else
  echo -e "${Y}Phát hiện lần chạy đầu tiên – bắt đầu setup...${N}"
  sleep 1
  do_setup
fi
