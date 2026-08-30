# 行程站：火车订票系统

面向“数据库系统课程设计”的 MySQL + Flask Web 项目。系统覆盖乘客订票和管理员运营管理，并将课程要求的完整性约束、视图、存储过程、触发器与并发控制落实在数据库中。

## 已实现功能

- 乘客端：注册、登录、按出发站/到达站/日期查询、选择席别、创建订单、查询订单、取消订单。
- 管理端：运营概览、日销售统计、最近订单、车站新增/查询/停用/删除、车次开售状态维护。
- 数据库：主键/外键/检查约束、`v_train_schedule_search` 与 `v_daily_sales` 视图、`sp_create_order` 与 `sp_cancel_order` 存储过程、订单与余票联动触发器。
- 并发订票：`sp_create_order` 在事务内通过 `SELECT ... FOR UPDATE` 锁定候选座位，配合座位状态条件更新，避免同一座位重复出售。

## 项目结构

```text
train-ticket-system/
├─ app.py                       # Flask 入口与路由
├─ config.py                    # 数据库配置
├─ database/
│  ├─ schema.sql                # 表、约束、视图、触发器
│  ├─ routines.sql              # 存储过程
│  └─ seed.sql                  # 演示数据
├─ templates/                   # Jinja 页面
├─ static/                      # CSS 与交互脚本
├─ tests/                       # 无数据库静态校验
└─ scripts/import_database.ps1  # 导入数据库脚本
```

## 环境要求

- Python 3.10+
- MySQL 8.0+（需要启用 InnoDB，字符集使用 utf8mb4）
- Windows PowerShell 或任意可运行 Python 的终端

## 快速启动

1. 创建数据库配置文件：

   ```powershell
   Copy-Item .env.example .env
   ```

   编辑 `.env`，填写本机 MySQL 的 `MYSQL_USER` 和 `MYSQL_PASSWORD`。

2. 导入数据库：

   ```powershell
   .\scripts\import_database.ps1 -MySqlUser root
   ```

   脚本会依次执行 `schema.sql`、`routines.sql`、`seed.sql`。如果 `mysql.exe` 未加入 PATH，可在执行时额外传入 `-MySqlExecutable 'C:\Program Files\MySQL\MySQL Server 8.0\bin\mysql.exe'`。

3. 安装 Python 依赖并启动：

   ```powershell
   python -m venv .venv
   .\.venv\Scripts\python.exe -m pip install -r requirements.txt
   .\.venv\Scripts\python.exe app.py
   ```

4. 打开 `http://127.0.0.1:5000`。

## 演示账号与数据

| 角色 | 用户名 | 密码 |
| --- | --- | --- |
| 管理员 | `admin` | `Admin@123` |
| 乘客 | `demo` | `Demo@123` |

测试数据包含广州南、深圳北、长沙南、武汉、北京西、上海虹桥等车站，以及 G1001、G6012、D2305 三个车次在未来两日的可售班次。首次导入后还会生成一笔已确认订单，方便演示统计视图。

## 数据库对象与课程要求映射

| 课程要求 | 落地方式 |
| --- | --- |
| 实体完整性 | 每张业务表使用主键，关键业务字段 `NOT NULL` |
| 参照完整性 | 用户、订单、车次、车站、座位之间使用外键 |
| 用户定义完整性 | `CHECK` 约束、状态枚举与触发器校验 |
| 视图 | `v_train_schedule_search`、`v_daily_sales` |
| 存储过程 | `sp_create_order`、`sp_cancel_order` |
| 触发器 | 订单取消自动释放座位；无已锁定座位时禁止插入车票 |
| 并发控制 | InnoDB 事务、行级锁、`FOR UPDATE`、状态条件更新 |

## 验证

不依赖 MySQL 的静态校验可运行：

```powershell
.\.venv\Scripts\python.exe -m unittest discover -s tests -v
```

MySQL 导入完成后，依次验证：

1. 使用 `demo` 登录，查询“广州南 → 北京西”，选择 G1001 二等座并订票。
2. 在“我的订单”取消刚创建的订单，再次查询该车次，余票应恢复。
3. 使用 `admin` 登录管理后台，查看订单和 `v_daily_sales` 统计。
4. 同时打开两个浏览器窗口抢最后一张某席别车票，只有一个订单应创建成功。

## 注意

这是教学项目，开发环境默认密钥仅用于本地演示。提交或部署前请更换 `.env` 中的 `FLASK_SECRET_KEY` 和数据库密码。
