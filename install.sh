#!/bin/bash
#===============================================================================
# WordPress + MariaDB 备份管理 - 主脚本
# 文件：install.sh
# 用途：执行环境检测和备份操作
#===============================================================================

# 获取脚本所在目录
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# 加载配置文件
if [ -f "${SCRIPT_DIR}/data.conf" ]; then
    source "${SCRIPT_DIR}/data.conf"
else
    echo "[ERROR] 配置文件 data.conf 不存在"
    exit 1
fi

# 生成时间戳
TIMESTAMP=$(date +%Y%m%d_%H%M%S)

# 设置日志文件路径
LOG_DIR="${SCRIPT_DIR}/log"
if [ ! -d "$LOG_DIR" ]; then
    mkdir -p "$LOG_DIR"
fi
LOG_FILE="${LOG_DIR}/backup_${TIMESTAMP}.log"

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

    if [ -d "$LOG_DIR" ]; then
        echo "$log_entry" >> "$LOG_FILE"
    fi
}

#===============================================================================
# 显示帮助信息
#===============================================================================

show_help() {
    cat << EOF
用法：$0 [选项]

选项：
    check       执行环境检测（推荐首先运行）
    backup      执行备份
    help        显示此帮助信息

示例：
    $0 check    # 检测环境
    $0 backup   # 执行备份

EOF
}

#===============================================================================
# 执行环境检测
#===============================================================================

run_check() {
    log "INFO" "开始执行环境检测..."

    if [ -f "${SCRIPT_DIR}/PATH.sh" ]; then
        chmod +x "${SCRIPT_DIR}/PATH.sh"
        "${SCRIPT_DIR}/PATH.sh"
        return $?
    else
        log "ERROR" "PATH.sh 脚本不存在"
        return 1
    fi
}

#===============================================================================
# 执行备份
#===============================================================================

run_backup() {
    log "INFO" "开始执行备份..."

    if [ -f "${SCRIPT_DIR}/modules/backup.sh" ]; then
        chmod +x "${SCRIPT_DIR}/modules/backup.sh"
        "${SCRIPT_DIR}/modules/backup.sh"
        return $?
    else
        log "ERROR" "备份模块不存在：modules/backup.sh"
        return 1
    fi
}

#===============================================================================
# 主程序
#===============================================================================

main() {
    echo "========================================"
    echo "  WordPress + MariaDB 备份管理脚本"
    echo "========================================"
    echo ""

    local action="${1:-help}"

    case "$action" in
        check)
            run_check
            ;;
        backup)
            run_backup
            ;;
        help|--help|-h)
            show_help
            ;;
        *)
            log "ERROR" "未知参数：${action}"
            show_help
            exit 1
            ;;
    esac
}

# 执行主程序
main "$@"
