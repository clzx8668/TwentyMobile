# CRUD 差距审计（按 Home / 列表 / 详情 / 编辑）

目标：用“可点到代码的位置”明确每个实体的 CRUD 是否闭环、是否一致、缺口在哪里，并按优先级给出后续迭代入口。

相关代码参考：
- Contacts：[contacts_screen.dart](file:///e:/devF/TwentyMobile/lib/presentation/contacts/contacts_screen.dart)、[contact_detail_screen.dart](file:///e:/devF/TwentyMobile/lib/presentation/contact_detail/contact_detail_screen.dart)、[edit_contact_sheet.dart](file:///e:/devF/TwentyMobile/lib/presentation/contacts/edit_contact_sheet.dart)
- Companies：[companies_screen.dart](file:///e:/devF/TwentyMobile/lib/presentation/companies/companies_screen.dart)、[company_detail_screen.dart](file:///e:/devF/TwentyMobile/lib/presentation/companies/company_detail_screen.dart)
- Tasks：[tasks_screen.dart](file:///e:/devF/TwentyMobile/lib/presentation/tasks/tasks_screen.dart)
- Notes：[note_card.dart](file:///e:/devF/TwentyMobile/lib/presentation/shared/note_card.dart)、[edit_note_sheet.dart](file:///e:/devF/TwentyMobile/lib/presentation/notes/edit_note_sheet.dart)
- Providers（乐观更新/状态回滚）：[providers.dart](file:///e:/devF/TwentyMobile/lib/core/di/providers.dart)
- 远端适配（GraphQL/Raw fallback）：[twenty_connector.dart](file:///e:/devF/TwentyMobile/lib/data/connectors/twenty_connector.dart)

状态标记：
- ✅ 已闭环
- ⚠️ 可用但不一致/体验欠佳
- ❌ 缺口（无入口/不工作/不对齐）

---

## Contacts

| 场景 | C | R | U | D | 说明 |
|---|---:|---:|---:|---:|---|
| Home（Today 快捷入口） | ✅ | ✅ | - | - | Home 通过 SpeedDial 可创建 Contact（[today_screen.dart](file:///e:/devF/TwentyMobile/lib/presentation/home/today_screen.dart)） |
| 列表（ContactsScreen） | ✅ | ✅ | ✅ | ✅ | 创建：AddContactSheet；编辑/删除：SwipeActionWrapper（[contacts_screen.dart](file:///e:/devF/TwentyMobile/lib/presentation/contacts/contacts_screen.dart)） |
| 详情（ContactDetailScreen） | - | ✅ | ✅ | ✅ | 详情提供编辑与删除按钮；提供 Note/语音 note 创建入口（[contact_detail_screen.dart](file:///e:/devF/TwentyMobile/lib/presentation/contact_detail/contact_detail_screen.dart)） |

已知差距/不一致：
- ⚠️ 创建 Contact 不支持选择 Company（仅编辑支持 company picker），导致“创建后立刻建关联”缺口。
- ⚠️ 远端 `city/jobTitle/updatedAt/additionalEmails/additionalPhones` 已被查询（见 `getContactById`），但本地模型/UI 未覆盖（详见 [field-matrix.md](file:///e:/devF/TwentyMobile/.trae/specs/enhance-crm-offline-sync/field-matrix.md)）。

---

## Companies

| 场景 | C | R | U | D | 说明 |
|---|---:|---:|---:|---:|---|
| Home | - | - | - | - | 当前 Home 未提供公司入口 |
| 列表（CompaniesScreen） | ✅ | ✅ | ✅ | ✅ | 创建：AddCompanySheet；编辑/删除：SwipeActionWrapper（[companies_screen.dart](file:///e:/devF/TwentyMobile/lib/presentation/companies/companies_screen.dart)） |
| 详情（CompanyDetailScreen） | - | ✅ | ✅ | ✅ | 可编辑/删除；domainName 可点击打开（[company_detail_screen.dart](file:///e:/devF/TwentyMobile/lib/presentation/companies/company_detail_screen.dart)） |

已知差距/不一致：
- ⚠️ Company 模型字段（logoUrl/industry/website）UI 已预留，但远端查询目前未取，导致详情页“额外信息”基本为空（除 employees/domainName 外）。
- ✅ Company 与 Contact 的关联读取已支持：公司详情页展示关联 contacts（[linked_contacts_widget.dart](file:///e:/devF/TwentyMobile/lib/presentation/shared/linked_contacts_widget.dart) + `getContactsByCompany`）。

---

## Tasks

| 场景 | C | R | U | D | 说明 |
|---|---:|---:|---:|---:|---|
| Home（Today 列表 + 快捷创建） | ✅ | ✅ | ✅ | ✅ | Home 可创建 quick task；Today 卡片支持编辑/删除/完成（[today_screen.dart](file:///e:/devF/TwentyMobile/lib/presentation/home/today_screen.dart)、[task_today_card.dart](file:///e:/devF/TwentyMobile/lib/presentation/home/widgets/task_today_card.dart)） |
| 列表（TasksScreen） | ✅ | ✅ | ✅ | ✅ | 创建：AddTaskSheet；编辑/删除：SwipeActionWrapper；完成：Checkbox（[tasks_screen.dart](file:///e:/devF/TwentyMobile/lib/presentation/tasks/tasks_screen.dart)） |
| 详情/编辑（EditTaskSheet 复用） | - | ✅ | ✅ | ✅ | 点击条目打开 EditTaskSheet，内含删除入口 |

已知差距/不一致：
- ❌ 创建 Task 缺少 body（详情）输入 UI：AddTaskSheet 仅有 title/due/contact；但字段元数据与编辑 UI 已支持 body（[tasks_screen.dart](file:///e:/devF/TwentyMobile/lib/presentation/tasks/tasks_screen.dart)）。
- ⚠️ 远端 `createTask` mutation 返回不含 body，若新增 body 后需考虑“本地立即回显 vs 重拉任务列表”的一致性策略。

---

## Notes

| 场景 | C | R | U | D | 说明 |
|---|---:|---:|---:|---:|---|
| Contact 详情（Related Notes） | ✅ | ✅ | ✅ | ❌ | 创建：_AddNoteSheet；编辑：NoteCard → EditNoteSheet；删除无入口（[contact_detail_screen.dart](file:///e:/devF/TwentyMobile/lib/presentation/contact_detail/contact_detail_screen.dart)、[note_card.dart](file:///e:/devF/TwentyMobile/lib/presentation/shared/note_card.dart)） |
| Company 详情（Related Notes） | ❌ | ✅ | ✅ | ❌ | 当前 create 逻辑不对齐：CompanyNotes.addNote 通过 `createNote(contactId: '')` 创建，无法正确绑定 company（[providers.dart](file:///e:/devF/TwentyMobile/lib/core/di/providers.dart#L379-L453)）；删除无入口 |

已知差距/不一致（优先级最高）：
- ❌ Company 维度新增 Note 的关联绑定缺口：应与 Contact Note 对齐为“两步创建 + target 绑定”，但目前只做了第一步且 targetPersonId 为空字符串，预期会产生“孤儿 note / 不回显”问题。
- ❌ Note 删除入口缺失：虽然 Provider 已实现 `deleteNote`（ContactNotes/CompanyNotes），但 UI 没有触发点（NoteCard 全屏仅有 edit/close）。
- ⚠️ Demo mode 检查不一致：Contact 新增 note 前检查 Demo；Company 新增 note 的 UI 层未调用 DemoUtils（但 Provider 会挡住）。

---

## 结论（为 Task 2/3 的落点提供依据）

P0（阻断/明显错误）：
- Notes：Company 新增 note 关联创建（绑定逻辑）❌
- Notes：删除入口缺失 ❌
- Tasks：创建 UI 缺少 body（与编辑/展示不一致）❌

P1（字段覆盖不足/体验问题）：
- Contacts：city/jobTitle/updatedAt/additionalEmails/additionalPhones 未落模型/未展示 ⚠️
- Companies：logoUrl/industry/website 未拉取，详情信息缺失 ⚠️

