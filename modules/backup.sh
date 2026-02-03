#!/bin/bash
#===============================================================================
# 备份模块
# 文件：modules/backup.sh
# 用途：备份 MariaDB 数据库和 WordPress 文件
# 依赖：data.conf
#===============================================================================

# 错误处理
set -e
trap 'log "ERROR" "备份失败"; cleanup_temp' ERR

# 清理临时文件
cleanup_temp() {
    if [ -n "$TEMP_DIR" ] && [ -d "$TEMP_DIR" ]; then
        rm -rf "$TEMP_DIR" 2>/dev/null || true
    fi
}

# 获取脚本所在目录
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# 加载配置文件
if [ -f "${SCRIPT_DIR}/data.conf" ]; then
    source "${SCRIPT_DIR}/data.conf"
else
    echo "[ERROR] 配置文件 data.conf 不存在"
    exit 1
fi

# 生成时间戳
TIMESTAMP=$(date +%Y%m%d_%H%M%S)

# 创建临时目录
TEMP_DIR=$(mktemp -d)
if [ ! -d "$TEMP_DIR" ]; then
    echo "[ERROR] 无法创建临时目录"
    exit 1
fi

# 设置日志文件
LOG_DIR="${SCRIPT_DIR}/log"
if [ ! -d "$LOG_DIR" ]; then
    mkdir -p "$LOG_DIR"
fi
LOG_FILE="${LOG_DIR}/backup_${TIMESTAMP}.log"

# 创建临时日志
TEMP_LOG="${TEMP_DIR}/backup.log"

#===============================================================================
# 日志函数
#===============================================================================

log() {
    local level="$1"
    local message="$2"
    local timestamp
    timestamp=$(date "+%Y-%m-%d %H:%M:%S")

    local log_entry="[${timestamp}] [${level}] ${message}"

    case "$level" in
        ERROR) echo -e "\033[31m${log_entry}\033[0m" >&2 ;;
        WARN)  echo -e "\033[33m${log_entry}\033[0m" ;;
        INFO)  echo -e "\033[32m${log_entry}\033[0m" ;;
        *)     echo "$log_entry" ;;
    esac

    echo "$log_entry" >> "$TEMP_LOG"
}

#===============================================================================
# 环境检查
#===============================================================================

check_environment() {
    log "INFO" "检查备份环境..."
    log "INFO" "WordPress 路径：${WP_ROOT}"
    log "INFO" "备份目录：${BACKUP_DIR}"

    # 检查备份目录
    if [ ! -d "$BACKUP_DIR" ]; then
        mkdir -p "$BACKUP_DIR"
    fi

    # 检查 WordPress 目录
    if [ ! -d "$WP_ROOT" ]; then
        log "ERROR" "WordPress 目录不存在：${WP_ROOT}"
        return 1
    fi

    # 检查必要命令
    if ! command -v mysqldump &> /dev/null; then
        log "ERROR" "mysqldump 命令未找到"
        return 1
    fi

    log "INFO" "环境检查通过"
    return 0
}

#===============================================================================
# 备份数据库
#===============================================================================

backup_database() {
    log "INFO" "开始备份数据库..."

    local db_file="${TEMP_DIR}/database.sql"

    # 导出数据库
    if mysqldump \
        -u "${DB_USER}" \
        -p"${DB_USER_PASS}" \
        -h "${DB_HOST}" \
        -P "${DB_PORT}" \
        --single-transaction \
        --routines \
        --triggers \
        --events \
        --hex-blob \
        --add-drop-table \
        "${DB_NAME}" > "$db_file" 2>&1; then

        local db_size
        db_size=$(du -h "$db_file" | cut -f1)
        log "INFO" "数据库备份成功：${db_size}"
        return 0
    else
        log "ERROR" "数据库备份失败"
        return 1
    fi
}

#===============================================================================
# 备份 WordPress 文件
#===============================================================================

backup_wordpress_files() {
    log "INFO" "开始备份 WordPress 文件..."

    local wp_tar="${TEMP_DIR}/wordpress.tar.gz"
    local wp_parent
    wp_parent=$(dirname "$WP_ROOT")
    local wp_name
    wp_name=$(basename "$WP_ROOT")

    log "INFO" "WordPress 父目录：${wp_parent}"
    log "INFO" "WordPress 目录名：${wp_name}"

    # 排除缓存和备份目录（简化模式）
    local exclude_params="--exclude=wp-content/cache --exclude=wp-content/updraft --exclude=wp-content/backups --exclude=*.log"

    # 打包文件（--exclude 必须放在目录参数之前）
    if tar -czf "$wp_tar" \
        ${exclude_params} \
        -C "$wp_parent" \
        "$wp_name" 2>&1; then

        local wp_size
        wp_size=$(du -h "$wp_tar" | cut -f1)
        log "INFO" "WordPress 文件备份成功：${wp_size}"
        return 0
    else
        local tar_error=$?
        log "ERROR" "WordPress 文件备份失败（错误码：${tar_error}）"
        return 1
    fi
}

#===============================================================================
# 创建备份包
#===============================================================================

create_backup_archive() {
    log "INFO" "创建备份包..."

    local backup_file="${BACKUP_DIR}/backup_${TIMESTAMP}.tar.gz"

    # 进入临时目录打包
    cd "$TEMP_DIR"

    # 创建压缩包
    if tar -czf "$backup_file" . 2>&1; then
        local backup_size
        backup_size=$(du -h "$backup_file" | cut -f1)
        log "INFO" "备份包创建成功：${backup_file} (${backup_size})"
        return 0
    else
        log "ERROR" "备份包创建失败"
        return 1
    fi
}

#===============================================================================
# 清理旧备份
#===============================================================================

cleanup_old_backups() {
    if [ -z "$KEEP_BACKUP_DAYS" ] || [ "$KEEP_BACKUP_DAYS" = "0" ]; then
        return 0
    fi

    log "INFO" "清理 ${KEEP_BACKUP_DAYS} 天前的旧备份..."

    local deleted=0
    while IFS= read -r -d '' file; do
        rm -f "$file" 2>/dev/null
        deleted=$((deleted + 1))
    done < <(find "$BACKUP_DIR" -maxdepth 1 -name "backup_*.tar.gz" -type f -mtime +"${KEEP_BACKUP_DAYS}" -print0 2>/dev/null)

    if [ $deleted -gt 0 ]; then
        log "INFO" "已清理 ${deleted} 个旧备份"
    fi

    return 0
}

#===============================================================================
# 验证备份
#===============================================================================

verify_backup() {
    local backup_file="${BACKUP_DIR}/backup_${TIMESTAMP}.tar.gz"

    if [ ! -f "$backup_file" ]; then
        log "ERROR" "备份文件不存在：${backup_file}"
        return 1
    fi

    local backup_size
    backup_size=$(stat -c%s "$backup_file" 2>/dev/null || stat -f%z "$backup_file" 2>/dev/null || echo "0")
    if [ "$backup_size" -eq 0 ]; then
        log "ERROR" "备份文件为空"
        return 1
    fi

    # 验证压缩包完整性
    if tar -tzf "$backup_file" &>/dev/null; then
        log "INFO" "备份验证通过"
        return 0
    else
        log "ERROR" "备份文件可能损坏"
        return 1
    fi
}

#===============================================================================
# 移动日志文件
#===============================================================================

move_log_file() {
    if [ -f "$TEMP_LOG" ] && [ -d "$LOG_DIR" ]; then
        mv "$TEMP_LOG" "$LOG_FILE" 2>/dev/null || cat "$TEMP_LOG" >> "$LOG_FILE"
    fi
}

#===============================================================================
# 显示备份摘要
#===============================================================================

show_summary() {
    local backup_file="${BACKUP_DIR}/backup_${TIMESTAMP}.tar.gz"

    log "INFO" "========================================"
    log "INFO" "备份完成"
    log "INFO" "========================================"
    log "INFO" "备份文件：${backup_file}"
    log "INFO" "还原命令："
    log "INFO" "  1. 解压：tar -xzf ${backup_file} -C /tmp/"
    log "INFO" "  2. 导入数据库：mysql -u ${DB_USER} -p${DB_USER_PASS} ${DB_NAME} < /tmp/database.sql"
    log "INFO" "  3. 解压文件：tar -xzf /tmp/wordpress.tar.gz -C $(dirname ${WP_ROOT})/"
}

#===============================================================================
# 主程序
#===============================================================================

main() {
    echo "========================================"
    echo "  备份模块"
    echo "========================================"
    echo ""

    log "INFO" "开始执行备份..."
    log "INFO" "时间戳：${TIMESTAMP}"

    # 设置清理陷阱
    trap cleanup_temp EXIT

    # 检查环境
    check_environment || exit 1

    # 备份数据库
    backup_database || exit 1

    # 备份文件
    backup_wordpress_files || exit 1

    # 创建备份包
    create_backup_archive || exit 1

    # 清理旧备份
    cleanup_old_backups || exit 1

    # 验证备份
    verify_backup || exit 1

    # 显示摘要
    show_summary

    # 移动日志
    move_log_file

    # 清理临时目录
    cleanup_temp

    echo ""
    echo -e "\033[32m[OK] 备份成功完成\033[0m"
}

# 执行主程序
main
