# Tasks

- [x] Task 1: 现状审计与字段矩阵落地
  - [x] 梳理 Contacts/Companies/Tasks/Notes 的字段矩阵（字段名、类型、必填、UI 展示/编辑、空值策略）
  - [x] 盘点并记录现有 CRUD 缺口与不一致点（按优先级：Home/列表/详情/编辑）
  - [x] 输出用于回归的用例清单（含断网/弱网/恢复网络）

- [x] Task 2: 修复 Notes 的 Company 关联创建与删除入口
  - [x] 扩展 Repository 能力以支持 Company Note 的创建并绑定（对齐 Contact Note 的“两步创建 + target 绑定”）
  - [x] 修复 Company 详情页“New Note”使其创建后可回显且正确关联
  - [x] 为 Note 增加删除 UI 入口（列表卡片或编辑 sheet 内）
  - [x] 统一 Contact/Company Notes 的 add/update/delete 行为与错误展示

- [x] Task 3: 完善 Tasks 创建字段（body）与 UI
  - [x] 在新增 Task 的 UI 中增加详情输入
  - [x] Provider/Repository 透传 body 到远端创建
  - [x] 确认列表与详情能展示 body（必要时补充 UI 展示）

- [x] Task 4: 引入离线实体存储（Offline Read）
  - [x] 选择并集成本地存储方案（Drift/Isar/Hive typed，优先可查询与迁移能力）
  - [x] 建立本地表/集合：contacts/companies/tasks/notes + meta（lastSyncAt 等）
  - [x] 调整数据读取链路：页面优先读取本地，再触发远端刷新回写本地
  - [x] 为列表与详情实现离线可读回退（无网络不白屏）

- [x] Task 5: 引入 Outbox（Offline Write）
  - [x] 设计 outbox 结构（operationId、entity、op、payload、status、retryCount、baseVersion、lastError）
  - [x] 改造 create/update/delete：本地落库 + 入队；在线时直发并回填远端结果
  - [x] 实现 outbox 合并（同实体连续编辑的 coalesce）以减少冲突与重复提交

- [x] Task 6: 同步引擎（自动/手动）与冲突处理
  - [x] 监听网络恢复与前台恢复触发 outbox flush
  - [x] 设置页增加“立即同步”入口并展示进度/失败原因
  - [x] 实现冲突检测（基于 updatedAt 或 baseVersion），阻止静默覆盖
  - [x] 提供冲突处理策略：保留本地覆盖 / 放弃本地采用远端

- [x] Task 7: 可观测性与回归验证
  - [x] 为所有远端请求与 outbox 操作补齐 source 标记与结构化错误日志
  - [x] 添加/完善测试或可重复验证脚本（至少覆盖：离线读、离线写、恢复网络 flush、冲突场景）
  - [x] 回归：Contacts/Companies/Tasks/Notes 全链路（在线/离线/恢复）通过

# Task Dependencies
- Task 2 depends on Task 1
- Task 3 depends on Task 1
- Task 4 depends on Task 1
- Task 5 depends on Task 4
- Task 6 depends on Task 5
- Task 7 depends on Task 2, Task 3, Task 4, Task 5, Task 6
