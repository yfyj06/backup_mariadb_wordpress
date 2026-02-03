#!/bin/bash
#===============================================================================
# 环境检测脚本
# 文件: PATH.sh
# 用途: 检测脚本运行所需的命令和环境
#===============================================================================

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 加载配置文件
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [ -f "${SCRIPT_DIR}/data.conf" ]; then
    source "${SCRIPT_DIR}/data.conf"
else
    echo -e "${RED}[ERROR] 配置文件 data.conf 不存在${NC}"
    exit 1
fi

# 统计变量
CHECK_COUNT=0
PASS_COUNT=0
FAIL_COUNT=0
WARN_COUNT=0

# ============================================================================
# 输出函数
# ============================================================================

pass() {
    echo -e "  ${GREEN}[PASS]${NC} $1"
    PASS_COUNT=$((PASS_COUNT + 1))
    CHECK_COUNT=$((CHECK_COUNT + 1))
}

fail() {
    echo -e "  ${RED}[FAIL]${NC} $1"
    FAIL_COUNT=$((FAIL_COUNT + 1))
    CHECK_COUNT=$((CHECK_COUNT + 1))
}

warn() {
    echo -e "  ${YELLOW}[WARN]${NC} $1"
    WARN_COUNT=$((WARN_COUNT + 1))
}

info() {
    echo -e "  ${BLUE}[INFO]${NC} $1"
}

ok() {
    echo -e "  ${GREEN}[OK]${NC} $1"
}

# ============================================================================
# 检测函数
# ============================================================================

# 检测必要命令
check_required_commands() {
    echo ""
    echo -e "${BLUE}=== 检测必要命令 ===${NC}"

    # 基础命令
    local commands=("wget" "tar" "mysql" "mysqldump")
    local missing=()

    for cmd in "${commands[@]}"; do
        if command -v "$cmd" &> /dev/null; then
            local version
            version=$($cmd --version 2>/dev/null | head -n1 | cut -d' ' -f1-3 || $cmd -V 2>/dev/null | head -n1 || echo "installed")
            ok "${cmd}: ${version}"
        else
            missing+=("$cmd")
            fail "${cmd}: 未安装"
        fi
    done

    if [ ${#missing[@]} -gt 0 ]; then
        echo ""
        warn "缺少必要命令: ${missing[*]}"
        info "请安装: apt-get install -y ${missing[*]}"
    fi
}

# 检测 PHP 环境
check_php() {
    echo ""
    echo -e "${BLUE}=== 检测 PHP 环境 ===${NC}"

    if command -v php &> /dev/null; then
        local php_version
        php_version=$(php -v 2>/dev/null | head -n1)
        ok "PHP 已安装: ${php_version}"

        # 检测必要扩展
        local extensions=("mysqli" "mbstring" "gd" "curl" "xml")
        local missing_ext=()

        for ext in "${extensions[@]}"; do
            if php -m 2>/dev/null | grep -qi "^${ext}\$"; then
                ok "  扩展 ${ext}: 已安装"
            else
                warn "  扩展 ${ext}: 未安装"
                missing_ext+=("$ext")
            fi
        done

        if [ ${#missing_ext[@]} -gt 0 ]; then
            info "建议安装扩展: apt-get install -y php-${php_version:0:1}-${missing_ext[0]}"
        fi
    else
        fail "PHP 未安装"
        info "WordPress 需要 PHP 环境，请先安装 PHP"
    fi
}

# 检测 MariaDB
check_mariadb() {
    echo ""
    echo -e "${BLUE}=== 检测 MariaDB ===${NC}"

    if command -v mysql &> /dev/null; then
        local mysql_version
        mysql_version=$(mysql --version 2>/dev/null | awk '{print $3, $4}' || echo "installed")
        ok "MariaDB 客户端: ${mysql_version}"

        # 检测服务状态
        if pgrep -x "mysqld" > /dev/null || pgrep -x "mariadbd" > /dev/null; then
            ok "MariaDB 服务: 运行中"
        else
            warn "MariaDB 服务: 未运行"
            info "请启动服务: systemctl start mariadb"
        fi

        # 测试数据库连接
        if mysql -u root -e "SELECT 1" &>/dev/null; then
            ok "数据库连接: 正常"
        elif mysql -u root -p"${DB_ROOT_PASS}" -e "SELECT 1" &>/dev/null; then
            ok "数据库连接: 正常（需要密码）"
        else
            warn "数据库连接: 无法连接"
            info "请检查 data.conf 中的数据库配置"
        fi
    else
        fail "MariaDB 客户端未安装"
        info "请安装: apt-get install -y mariadb-client"
    fi
}

# 检测 WordPress
check_wordpress() {
    echo ""
    echo -e "${BLUE}=== 检测 WordPress ===${NC}"

    if [ -d "$WP_ROOT" ]; then
        ok "WordPress 目录: ${WP_ROOT}"

        # 检查必要文件
        local required_files=("wp-config-sample.php" "wp-settings.php" "index.php")
        local missing_files=()

        for file in "${required_files[@]}"; do
            if [ -f "${WP_ROOT}/${file}" ]; then
                ok "  文件 ${file}: 存在"
            else
                fail "  文件 ${file}: 缺失"
                missing_files+=("$file")
            fi
        done

        # 获取版本
        if [ -f "${WP_ROOT}/wp-includes/version.php" ]; then
            local wp_version
            wp_version=$(grep "wp_version =" "${WP_ROOT}/wp-includes/version.php" | cut -d\' -f2 2>/dev/null || echo "unknown")
            ok "WordPress 版本: ${wp_version}"
        fi
    else
        warn "WordPress 未安装"
        info "WordPress 路径: ${WP_ROOT}"
        info "请手动安装 WordPress"
    fi
}

# 检测目录权限
check_directories() {
    echo ""
    echo -e "${BLUE}=== 检测目录权限 ===${NC}"

    # 检测备份目录
    if [ -d "$BACKUP_DIR" ]; then
        if [ -w "$BACKUP_DIR" ]; then
            ok "备份目录: ${BACKUP_DIR} (可写)"
        else
            warn "备份目录: ${BACKUP_DIR} (不可写)"
            info "请修改权限: chmod 755 ${BACKUP_DIR}"
        fi
    else
        info "备份目录不存在，将自动创建"
        if mkdir -p "$BACKUP_DIR" 2>/dev/null; then
            ok "备份目录创建成功: ${BACKUP_DIR}"
        else
            fail "备份目录创建失败: ${BACKUP_DIR}"
        fi
    fi

    # 检测日志目录
    if [ -d "$LOG_DIR" ]; then
        if [ -w "$LOG_DIR" ]; then
            ok "日志目录: ${LOG_DIR} (可写)"
        else
            warn "日志目录: ${LOG_DIR} (不可写)"
        fi
    else
        info "日志目录不存在，将自动创建"
        if mkdir -p "$LOG_DIR" 2>/dev/null; then
            ok "日志目录创建成功: ${LOG_DIR}"
        else
            fail "日志目录创建失败: ${LOG_DIR}"
        fi
    fi
}

# 检测 Web 服务
check_web_server() {
    echo ""
    echo -e "${BLUE}=== 检测 Web 服务 ===${NC}"

    # 检测 Nginx
    if command -v nginx &> /dev/null; then
        local nginx_version
        nginx_version=$(nginx -v 2>&1 | awk -F'/' '{print $2}' || echo "installed")
        ok "Nginx: ${nginx_version}"

        if pgrep -x "nginx" > /dev/null; then
            ok "Nginx 服务: 运行中"
        else
            warn "Nginx 服务: 未运行"
        fi
    else
        info "Nginx: 未安装"
    fi

    # 检测 Apache
    if command -v apache2 &> /dev/null || command -v httpd &> /dev/null; then
        ok "Apache: 已安装"
        if pgrep -x "apache2" > /dev/null || pgrep -x "httpd" > /dev/null; then
            ok "Apache 服务: 运行中"
        else
            warn "Apache 服务: 未运行"
        fi
    else
        info "Apache: 未安装"
    fi
}

# ============================================================================
# 主程序
# ============================================================================

main() {
    echo "========================================"
    echo "  环境检测脚本"
    echo "========================================"
    echo ""
    echo "配置文件: ${SCRIPT_DIR}/data.conf"
    echo "WordPress 路径: ${WP_ROOT}"
    echo "备份目录: ${BACKUP_DIR}"
    echo ""

    # 执行各项检测
    check_required_commands
    check_php
    check_mariadb
    check_wordpress
    check_directories
    check_web_server

    # 输出检测摘要
    echo ""
    echo "========================================"
    echo "  检测摘要"
    echo "========================================"
    echo -e "  检查项目: ${CHECK_COUNT}"
    echo -e "  ${GREEN}通过: ${PASS_COUNT}${NC}"
    echo -e "  ${RED}失败: ${FAIL_COUNT}${NC}"
    echo -e "  ${YELLOW}警告: ${WARN_COUNT}${NC}"
    echo "========================================"

    if [ $FAIL_COUNT -gt 0 ]; then
        echo ""
        echo -e "${RED}[ERROR] 检测未通过，请解决上述问题后重试${NC}"
        exit 1
    elif [ $WARN_COUNT -gt 0 ]; then
        echo ""
        echo -e "${YELLOW}[WARN] 检测完成，但存在警告信息${NC}"
        exit 0
    else
        echo ""
        echo -e "${GREEN}[OK] 环境检测通过${NC}"
        exit 0
    fi
}

# 执行主程序
main "$@"
