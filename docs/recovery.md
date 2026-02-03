---
AIGC:
    ContentProducer: Minimax Agent AI
    ContentPropagator: Minimax Agent AI
    Label: AIGC
    ProduceID: "00000000000000000000000000000000"
    PropagateID: "00000000000000000000000000000000"
    ReservedCode1: 3046022100e23ec7de6f92dc2fcd05c1f959c78e2106bcb5a8b2e3242bb43de3db962ead46022100df3aa9cc883e01c9cf94872e8b2edb46799a97b6b74dafd36a7244c09d4f8c74
    ReservedCode2: 3045022018025a3fb308c37e559a879243e5fe7b446bdff8ba9de7e1d35d1b14be365ac0022100df932225f97820ac04c5c0aa5cf8cd364cf787a34e3e5f6f759d659bb5b88336
---

# 数据恢复指南

本文档介绍如何从备份恢复 WordPress 网站和 MariaDB 数据库。

## 恢复前准备

1. 确认备份文件完整
2. 确保目标环境已安装相同版本的软件
3. 准备好足够的磁盘空间

## 恢复数据库

### 步骤 1：解压备份文件

```bash
cd /tmp
tar -xzf /path/to/backup_YYYYMMDD_HHMMSS.tar.gz
```

### 步骤 2：导入数据库

```bash
mysql -u root -p your_database_name < database.sql
```

或使用源数据库用户：

```bash
mysql -u your_db_user -p your_db_name < database.sql
```

### 步骤 3：验证数据库

```bash
mysql -u your_db_user -p -e "SHOW TABLES FROM your_db_name;"
```

## 恢复网站文件

### 步骤 1：解压 WordPress 文件

```bash
cd /var/www
tar -xzf /tmp/wordpress.tar.gz
```

### 步骤 2：设置文件权限

```bash
chown -R www-data:www-data /var/www/wordpress
find /var/www/wordpress -type d -exec chmod 755 {} \;
find /var/www/wordpress -type f -exec chmod 644 {} \;
```

### 步骤 3：检查关键文件

确认以下文件存在：

- `wp-config.php`
- `wp-settings.php`
- `index.php`
- `.htaccess`（如果使用 Apache）

## 恢复后的检查清单

1. **数据库连接测试**：访问网站，确认数据库连接正常
2. **后台登录**：尝试登录 WordPress 管理后台
3. **文章检查**：确认文章、页面数据完整
4. **媒体文件**：检查上传的图片等媒体文件
5. **插件状态**：检查插件是否需要重新激活
6. **固定链接**：访问几篇文章，确认固定链接正常

## 常见问题

### 问题 1：数据库导入失败

**可能原因**：
- 数据库用户权限不足
- 数据库不存在
- SQL 文件损坏

**解决方法**：
1. 确保数据库已创建：`CREATE DATABASE your_db_name;`
2. 检查导入用户是否有足够权限

### 问题 2：文件权限问题

**症状**：网站显示 403 错误或无法上传文件

**解决方法**：
```bash
chown -R www-data:www-data /var/www/wordpress
chmod -R 755 /var/www/wordpress/wp-content/uploads
```

### 问题 3：图片显示不出来

**可能原因**：文件权限不正确

**解决方法**：
```bash
find /var/www/wordpress -type f -name "*.jpg" -o -name "*.png" | xargs chmod 644
```

## 定期测试恢复流程

建议定期（每月一次）测试恢复流程，确保备份文件可用。

```bash
# 完整恢复测试
cd /tmp
mkdir test_restore
cd test_restore
tar -xzf /path/to/backup.tar.gz
# 按照上述步骤测试恢复
rm -rf /tmp/test_restore
```
