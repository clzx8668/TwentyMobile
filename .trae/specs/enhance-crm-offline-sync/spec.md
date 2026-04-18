# PocketCRM（Twenty）功能完善与离线同步 Spec

## Why
当前 App 已能连接 Twenty 并完成基础数据读取，但界面字段覆盖不足、部分 CRUD 存在缺口，且缺少离线存储与异步同步机制，导致无网络无法稳定使用与存在数据冲突风险。

## What Changes
- 完善 Contacts / Companies / Tasks / Notes 的字段展示与增删改查闭环
- 修复 Company 详情页新增 Note 的“关联绑定”逻辑
- 增加 Notes 删除入口与一致的删除体验
- 引入离线优先的数据架构：本地实体存储（可读）+ Outbox 写队列（可写）
- 引入同步引擎：网络恢复自动同步 + 手动同步入口 + 冲突检测与处理
- 增强日志与可观测性：为数据请求与同步动作统一 `source` 标记与错误聚合

## Impact
- Affected specs: 认证与 workspace 头注入、CRUD（contacts/companies/tasks/notes）、离线缓存、异步同步、冲突处理、日志与可观测性
- Affected code:
  - 数据访问： [twenty_connector.dart](file:///e:/devF/TwentyMobile/lib/data/connectors/twenty_connector.dart)
  - Repository 接口： [crm_repository.dart](file:///e:/devF/TwentyMobile/lib/domain/repositories/crm_repository.dart)
  - Providers/状态： [providers.dart](file:///e:/devF/TwentyMobile/lib/core/di/providers.dart)
  - UI：Contacts/Companies/Tasks/Notes 相关 screen/sheet/widget
  - 本地存储： [storage_service.dart](file:///e:/devF/TwentyMobile/lib/core/utils/storage_service.dart)（扩展/并新增实体存储与 outbox）

## ADDED Requirements

### Requirement: 字段矩阵与覆盖基线
系统 SHALL 提供一份“字段矩阵”，用于描述每个实体（Contact/Company/Task/Note）的字段来源、当前模型、UI 覆盖与缺口，并用于驱动迭代顺序。

#### Scenario: 字段矩阵生成
- **WHEN** 开发者执行字段梳理流程
- **THEN** 产出包含字段名、类型、是否必填、UI 展示/编辑位置、默认值/空值策略的矩阵

### Requirement: Notes 完整闭环（含公司关联与删除）
系统 SHALL 支持在 Contact 与 Company 详情页创建、编辑、删除 Note，并保证 Note 与对应对象正确关联。

#### Scenario: Company 详情页新增 Note 成功并可回显
- **WHEN** 用户在 Company 详情页输入内容并保存
- **THEN** 本地列表立即出现该 Note
- **AND** 在线时远端创建成功后，该 Note 在重新进入页面/刷新后仍可见
- **AND** Note 与该 Company 正确关联（不会出现在其他 Company 或变成“孤儿 Note”）

#### Scenario: 删除 Note
- **WHEN** 用户在 Note 的操作入口选择删除并确认
- **THEN** Note 从本地 UI 中移除
- **AND** 在线时远端删除成功；离线时进入 outbox，联网后补删

### Requirement: Tasks 创建支持 body
系统 SHALL 允许创建 Task 时填写标题与详情（body），并与 Twenty 对应字段一致写入。

#### Scenario: 创建带详情的 Task
- **WHEN** 用户创建 Task 并填写详情
- **THEN** Task 列表/详情可以展示该详情
- **AND** 在线时远端字段与本地一致

### Requirement: 离线可读（Offline Read）
系统 SHALL 在无网络时可浏览最近一次同步的 Contacts/Companies/Tasks/Notes 列表与详情。

#### Scenario: 断网后进入列表与详情
- **WHEN** 设备无网络且用户进入 Contacts/Companies/Tasks 页面
- **THEN** 页面展示本地缓存的数据（非空则立即可见）
- **AND** 不因网络请求失败导致白屏或无限 loading

### Requirement: 离线可写（Offline Write / Outbox）
系统 SHALL 在无网络时允许对 Contacts/Companies/Tasks/Notes 执行新增/编辑/删除，并以 outbox 队列形式在网络恢复后自动或手动补发到远端。

#### Scenario: 离线编辑后自动同步
- **WHEN** 用户离线编辑一个 Contact 并保存
- **THEN** UI 立即反映改动并持久化到本地存储
- **AND** 该操作进入 outbox
- **WHEN** 网络恢复
- **THEN** outbox 自动 flush，远端数据与本地一致

### Requirement: 同步与冲突防护
系统 SHALL 提供自动同步与手动同步能力，并在检测到冲突时阻止静默覆盖，要求用户选择处理方式或采取默认安全策略。

#### Scenario: 冲突检测与处理（默认安全）
- **GIVEN** 本地对某实体有未同步更新
- **AND** 远端同一实体已被其他客户端更新
- **WHEN** 同步 flush 该实体更新
- **THEN** 系统标记冲突并不进行静默覆盖
- **AND** 提供至少一种可执行策略：保留本地覆盖 / 放弃本地采用远端

### Requirement: 同步可观测性
系统 SHALL 对所有远端请求与 outbox 操作提供可定位的 `source` 与结构化错误信息，便于排查“single request”限制、鉴权与字段不匹配问题。

#### Scenario: 同步失败可定位
- **WHEN** outbox flush 发生失败
- **THEN** 日志包含实体、操作类型、source、错误摘要与可重试信息

## MODIFIED Requirements

### Requirement: 远端请求头注入（workspace）
系统 SHALL 对所有 GraphQL/HTTP POST 请求注入 `Authorization` 与 `x-workspace-id`，并对 token 与 instance URL 做去空白与归一化处理。

#### Scenario: 任意数据请求满足头要求
- **WHEN** App 发起任意 CRUD 请求
- **THEN** 请求包含 `Authorization: Bearer <token>`
- **AND** 请求包含 `x-workspace-id: <workspaceId>`

### Requirement: 复杂请求降级（避免 single request 限制）
系统 SHALL 在遇到服务端 “single request/复杂查询限制” 时降级为更简单的查询或原生 HTTP POST（按当前 connector 策略延伸到同步引擎）。

#### Scenario: 遇到限制时仍可取数
- **WHEN** 服务端返回不可单次执行类错误
- **THEN** 系统使用 simple/raw 通道重试并返回可用数据或明确错误提示

## REMOVED Requirements
无

