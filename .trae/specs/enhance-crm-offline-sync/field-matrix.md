# 字段矩阵（Contacts / Companies / Tasks / Notes）

本矩阵用于明确：
- Twenty 远端字段（GraphQL）→ 本地 Domain Model 的映射现状
- UI 展示/编辑覆盖情况（列表/详情/编辑/创建）
- 空值策略与已知缺口（为 Task 2+ 的修复与离线同步打基线）

代码参考：
- Repository 接口：[crm_repository.dart](file:///e:/devF/TwentyMobile/lib/domain/repositories/crm_repository.dart)
- Twenty Connector：[twenty_connector.dart](file:///e:/devF/TwentyMobile/lib/data/connectors/twenty_connector.dart)
- 字段渲染元数据：[entity_field_metadata.dart](file:///e:/devF/TwentyMobile/lib/presentation/shared/dynamic_fields/entity_field_metadata.dart)

---

## Contact（Person）

主要 UI：
- 列表：[contacts_screen.dart](file:///e:/devF/TwentyMobile/lib/presentation/contacts/contacts_screen.dart)
- 详情：[contact_detail_screen.dart](file:///e:/devF/TwentyMobile/lib/presentation/contact_detail/contact_detail_screen.dart)
- 编辑：[edit_contact_sheet.dart](file:///e:/devF/TwentyMobile/lib/presentation/contacts/edit_contact_sheet.dart)

| 远端字段（Twenty） | 本地模型字段 | 类型 | 创建/编辑 | UI 展示 | 空值策略 | 备注/缺口 |
|---|---|---|---|---|---|---|
| `id` | `Contact.id` | `String` | N/A | 列表/详情（路由 key） | N/A | 已覆盖 |
| `name.firstName` | `Contact.firstName` | `String` | 创建必填；编辑可改 | 列表 title；详情 title | 空字符串兜底 | 已覆盖 |
| `name.lastName` | `Contact.lastName` | `String` | 创建必填；编辑可改 | 列表 title；详情 title | 空字符串兜底 | 已覆盖 |
| `emails.primaryEmail` | `Contact.email` | `String?` | 创建可选；编辑可改 | 列表动态字段；详情 email tile | 详情显示 `No email` | 已覆盖；未覆盖 additionalEmails |
| `phones.primaryPhoneCallingCode` + `phones.primaryPhoneNumber` | `Contact.phone` | `String?` | 创建可选；编辑可改 | 列表动态字段；详情 phone tile | 详情显示 `No phone` | 本地拼接为 E.164-ish 字符串；未覆盖 additionalPhones |
| `avatarUrl` | `Contact.avatarUrl` | `String?` | 不可编辑 | 列表头像；详情头像 | 空则用首字母占位 | 已覆盖（仅 http 开头保留） |
| `company.id` | `Contact.companyId` | `String?` | 仅编辑支持；创建不支持 | 无直接展示 | N/A | 创建缺口：AddContactSheet 不支持选择 company |
| `company.name` | `Contact.companyName` | `String?` | 仅编辑间接（通过 companyId） | 列表动态字段；详情副标题 | 不展示则隐藏区域 | 已覆盖（兼容 Map `{text: ...}`） |
| `createdAt` | `Contact.createdAt` | `DateTime?` | 不可编辑 | 详情未展示 | N/A | 已解析但未用于 UI |
| `updatedAt` | `Contact.updatedAt` | `DateTime?` | 不可编辑 | 未展示 | N/A | 远端有查询，但 [contact.dart](file:///e:/devF/TwentyMobile/lib/domain/models/contact.dart) 当前未赋值（永远为 null） |
| `city` | 无 | - | - | 未展示 | - | 远端在 `getContactById` 查询，但未落到本地模型 |
| `jobTitle` | 无 | - | - | 未展示 | - | 同上 |
| `emails.additionalEmails` / `phones.additionalPhones` | 无 | - | - | 未展示 | - | 详情查询包含，但未落模型/未展示 |

---

## Company

主要 UI：
- 列表 & 创建/编辑 Sheet：[companies_screen.dart](file:///e:/devF/TwentyMobile/lib/presentation/companies/companies_screen.dart)
- 详情：[company_detail_screen.dart](file:///e:/devF/TwentyMobile/lib/presentation/companies/company_detail_screen.dart)

| 远端字段（Twenty） | 本地模型字段 | 类型 | 创建/编辑 | UI 展示 | 空值策略 | 备注/缺口 |
|---|---|---|---|---|---|---|
| `id` | `Company.id` | `String` | N/A | 列表/详情（路由 key） | N/A | 已覆盖 |
| `name` | `Company.name` | `String` | 创建必填；编辑可改 | 列表 title；详情 title | 空字符串兜底 | 已覆盖（兼容 Map `{text: ...}`） |
| `domainName.primaryLinkUrl` | `Company.domainName` | `String?` | 创建可选；编辑可改/可清空 | 列表动态字段；详情可点击打开网站 | 空则不展示 | `fromTwenty` 会去掉协议用于展示 |
| `employees` | `Company.employeesCount` | `int?` | 不可编辑 | 列表动态字段；详情 Employees tile | 空则不展示 | 已覆盖（字段名不一致：employees → employeesCount） |
| `createdAt` | `Company.createdAt` | `DateTime?` | 不可编辑 | 未展示 | N/A | 已解析但未用于 UI |
| `logoUrl` | `Company.logoUrl` | `String?` | 不可编辑 | 详情头像 | 空则默认图标 | 远端查询当前未取该字段，导致 UI 基本为空 |
| `industry` | `Company.industry` | `String?` | 不可编辑 | 详情 Industry tile | 空则不展示 | 远端查询当前未取该字段 |
| `website` | `Company.website` | `String?` | 不可编辑 | 未展示 | - | 远端查询当前未取该字段 |

---

## Task

主要 UI：
- 列表/创建/编辑：[tasks_screen.dart](file:///e:/devF/TwentyMobile/lib/presentation/tasks/tasks_screen.dart)
- 任务字段元数据（列表副文案）：[entity_field_metadata.dart](file:///e:/devF/TwentyMobile/lib/presentation/shared/dynamic_fields/entity_field_metadata.dart)

| 远端字段（Twenty） | 本地模型字段 | 类型 | 创建/编辑 | UI 展示 | 空值策略 | 备注/缺口 |
|---|---|---|---|---|---|---|
| `id` | `Task.id` | `String` | N/A | 列表 key | N/A | 已覆盖 |
| `title` | `Task.title` | `String` | 创建必填；编辑可改 | 列表主标题；编辑 sheet | 空字符串兜底 | 已覆盖 |
| `status` | `Task.completed` | `bool?` | 列表 checkbox；编辑可改 | 列表 checkbox + 样式 | `null` 视为未完成 | 远端 DONE/非 DONE 映射为 bool |
| `dueAt` | `Task.dueAt` | `DateTime?` | 创建可选；编辑可改/可清空 | 列表到期提示；动态字段 | 空则不展示 | 已覆盖（有 clearDueDate） |
| `bodyV2.blocknote` | `Task.body` | `String?` | 编辑 sheet 支持；创建 UI 缺口 | 列表动态字段（Details） | 空则不展示 | 创建缺口：AddTaskSheet 未提供 body 输入；同时 createTask mutation 返回不含 body（UI 需依赖本地回填/重拉） |
| `taskTargets` / target person | `Task.contactId` / `Task.contactName` | `String?` | 创建可选绑定 contact | 列表 chip 展示 | 空则隐藏 | 远端查询任务列表未内联 targets，UI 通过额外查询 [linked_contacts_widget.dart](file:///e:/devF/TwentyMobile/lib/presentation/shared/linked_contacts_widget.dart) 展示联系人 |
| `createdAt` | `Task.createdAt` | `DateTime?` | 不可编辑 | 未展示 | - | 已解析但未用于 UI |

---

## Note

主要 UI：
- Contact 详情相关 notes：[contact_detail_screen.dart](file:///e:/devF/TwentyMobile/lib/presentation/contact_detail/contact_detail_screen.dart)
- Company 详情相关 notes：[company_detail_screen.dart](file:///e:/devF/TwentyMobile/lib/presentation/companies/company_detail_screen.dart)
- Note 卡片（全屏查看 + 编辑入口）：[note_card.dart](file:///e:/devF/TwentyMobile/lib/presentation/shared/note_card.dart)
- Note 编辑：[edit_note_sheet.dart](file:///e:/devF/TwentyMobile/lib/presentation/notes/edit_note_sheet.dart)

| 远端字段（Twenty） | 本地模型字段 | 类型 | 创建/编辑 | UI 展示 | 空值策略 | 备注/缺口 |
|---|---|---|---|---|---|---|
| `id` | `Note.id` | `String` | N/A | 列表 key | N/A | 已覆盖 |
| `bodyV2.blocknote` | `Note.body` | `String` | 创建/编辑支持 | NoteCard 渲染；编辑 sheet 文本编辑 | 空字符串兜底 | 当前实现将 blocknote JSON 字符串直接存入 `body`（渲染依赖 BlockNoteRenderer） |
| `createdAt` | `Note.createdAt` | `DateTime?` | 不可编辑 | NoteCard 底部时间；全屏顶部时间 | 空则不展示 | 已覆盖 |
| `updatedAt` | 无 | - | - | 未展示 | - | 远端查询包含 updatedAt，但本地模型未存 |
| `targetPersonId` / `targetCompanyId`（通过 NoteTarget 关联） | `Note.contactId` / `Note.companyId` | `String?` | 关联由业务层控制 | UI 通过上下文传参（contactId/companyId） | - | 本地模型字段存在但 `fromTwenty` 未赋值；依赖“从哪个详情页进入”来决定上下文 |
| 删除 | - | - | 有 Provider 方法但 UI 缺口 | 无 | - | ContactNotes/CompanyNotes 均有 `deleteNote`，但 UI 没有删除入口（仅编辑/关闭） |

