# 表格视图增强（颜色/列配置/冻结列）规格说明

## 背景
当前 App 已在 Home / Contacts / Companies / Tasks 主页面支持“列表/表格”视图切换，并由 JSON UI 配置驱动渲染。现有表格视图还存在以下体验问题需要完善：
1. 表格内容文字颜色偏灰，观感不一致。
2. 表格视图缺少类似 Twenty 的“字段显示/隐藏”自定义入口。
3. 表格视图需要压缩前两列空间，并在左右滑动时冻结（固定）前两列。

## 目标
- 表格内容（header + cell）在浅色/深色主题下都使用“正常可读”的前景色，并与 App 主题一致。
- 在表格视图右上角提供“字段显示/隐藏”按钮，支持勾选列显示状态并持久化到本地（离线可用）。
- 表格横向滚动时冻结首列；同时尽量压缩前两列宽度，其他列可横向滚动查看。
- 所有表格字段支持筛选和排序；并在表格底部提供汇总、记录条数设置与页码跳转。
- 字段配置面板支持字段前后位置调整（列顺序重排）。

## 非目标
- 不做复杂的列拖拽排序（后续可扩展）。
- 不做服务端配置写回（仅本地个性化覆盖 UI 配置的默认列集合）。
- 不引入新的第三方 DataTable 扩展库（如 DataTable2）作为强依赖，优先使用现有 Flutter 组件完成。

## 需求与验收标准
### 1) 颜色修复
- 表头与内容文字颜色应使用 `colorScheme.onSurface`（或同等可读颜色），不应出现整体“灰/淡到像 disabled”的效果。
- 行选中/点击态不影响可读性；空态文本颜色仍可略淡。

验收：
- 在浅色主题：表格 cell 文本与列表模式文本同等可读。
- 在深色主题：表格 cell 文本不发灰、不低对比度。

### 2) 字段显示/隐藏按钮
- 表格视图右上角新增按钮（建议 icon：`view_column` / `tune`），点击打开“字段”面板：
  - 展示当前页面可用列列表（来源：JSON UI `tableColumns` + 内置列注册表支持的 keys）。
  - 每一项可勾选显示/隐藏。
  - 至少保留 2 列可见（与冻结列需求一致；若用户取消到 <2 列则阻止或自动恢复）。
- 配置需按页面维度持久化：`table_columns:<pageKey>`。
- 离线可用：无网络时仍加载并应用本地自定义列集。
- 与远端 UI 配置兼容：远端更新 `tableColumns` 后，本地自定义列集作为覆盖（仅对 keys 取交集，未知 key 忽略）。

验收：
- 每个页面独立保存列显示状态，切换 Tab/重启 App 后保持。
- 在 JSON UI 配置加载失败回退 assets 时仍生效。

### 3) 冻结首列 + 压缩前两列宽度
- 表格模式下默认冻结“显示顺序的首列”。
- 冻结列在横向滚动时保持固定，右侧列可横向滚动。
- 前两列尽量压缩：
  - 设定合理的固定宽度/最大宽度（如 title/name 列 160，status/company 列 120，可按实体微调）。
  - 文本超出以省略号截断（`TextOverflow.ellipsis`）。
- 垂直滚动时左右两侧行必须同步滚动，避免行错位。

技术约束：
- Flutter `DataTable` 原生不支持 frozen columns，需要自定义实现：
  - 将表格拆分为“左侧冻结区 + 右侧可横向滚动区”，并通过两个垂直 `ScrollController` 同步滚动位置。
  - 右侧区域外层用一个横向 `SingleChildScrollView` 包裹（横向仅影响右侧）。

验收：
- 横向滚动时首列不动，其他列随横向滚动。
- 垂直滚动时左右两侧行始终对齐。

### 4) 全字段筛选与排序
- 每个表格页面支持按字段筛选（字符串包含匹配）与排序（升序/降序）。
- 筛选与排序作用于“当前可见列集合”；若列被隐藏，该列筛选条件自动忽略。
- 默认排序可为空（按原数据顺序）；用户可清除排序。
- 交互风格贴近 Twenty：筛选/排序入口以紧凑图标呈现在每个列标题行内，而不是独立工具栏。

验收：
- 对联系人/公司/任务字段均可输入筛选条件并立即生效。
- 对任意可见列可执行升序/降序排序。

### 7) 筛选弹窗升级（Twenty 风格）
- 点击任意列标题内的“筛选”图标，弹出底部 Sheet（BottomSheet）进行筛选设置：
  - 支持操作符选择：`contains` / `equals` / `startsWith`。
  - 支持输入值（单行输入）。
  - 支持 Apply / Clear / Cancel。
- 多列筛选可叠加（AND 关系）。
- 筛选图标需体现“已启用筛选”的状态（例如实心/高亮）。

验收：
- 任意字段可打开筛选 Sheet 并切换操作符。
- Apply 后立即生效；Clear 后该列筛选条件移除；Cancel 不改变现有条件。
- 多列同时设置筛选条件时结果正确（AND）。

### 8) 筛选弹窗稳定性（必须修复）
- 点击筛选按钮后必须稳定展示 BottomSheet，不允许出现“仅弹出输入法但面板内容不显示”的情况。
- 不允许出现红屏（RenderBox layout / assertion）导致界面不可用。

验收：
- 真机（Android 14）连续快速点击不同列的筛选按钮 10 次，不出现红屏且每次都能看到 BottomSheet 完整内容（操作符 + 输入框 + 按钮）。

### 9) 冻结首列 Twenty 对齐（窄宽 + 多选 + 图标）
- 横向滚动冻结的首列改为“选择列”，宽度尽量窄，风格对齐 Twenty：
  - 固定展示多选框（checkbox）+ 实体图标（或首字母圆形图标），不展示长文本。
  - 该列始终冻结（横向滚动不动）。
  - 勾选支持多选，并在表格顶部/底部展示已选数量（可选）。
- 现有第一条数据字段列（例如 contacts.name / tasks.title）移动到可横向滚动区域中，避免冻结列过宽。

验收：
- 横向滚动时冻结列仅占用窄宽空间（checkbox + icon），与 Twenty 表格样式一致。
- 勾选多行后不影响筛选/排序/分页逻辑（筛选/翻页不会导致崩溃；必要时清除不可见行的 selection 或保留但不显示计数以避免困惑）。

### 5) 字段顺序调整
- 列配置面板在显示/隐藏基础上新增“前后位置调整”（拖拽重排）。
- 应用后表格列顺序立即更新，并按 pageKey 持久化。

验收：
- 用户调整列顺序后，离开页面再返回顺序保持一致。

### 6) 底部汇总、条数与跳页
- 表格底部展示汇总信息：总记录数、当前展示区间、当前页/总页数。
- 支持记录条数设置（如 10/20/50/100）。
- 支持页码跳转与前后翻页。

验收：
- 修改每页条数后分页立即重算。
- 输入页码跳转可生效并具备边界保护。

## 设计方案
### 组件层
1. `TableView` 增强：
   - 新增可选参数：
     - `frozenColumnCount`（默认 0；实体列表默认 2）。
     - `columnWidthHints`（按列 key 定义 width/min/max；默认提供 contacts/companies/tasks 的建议值）。
     - `onConfigureColumns`（由页面顶部按钮触发）。
   - 当 `frozenColumnCount > 0` 且 `columns.length > frozenColumnCount` 时，使用 `FrozenTableView` 渲染；否则使用现有 `DataTable` 渲染。
2. 新增 `FrozenTableView<T>`（Stateful）：
   - 输入：`columns/rows/frozenColumnCount/widthHints/onRowTap`。
   - 输出：左右分区 + 滚动同步 + 右侧横向滚动。
3. 新增 `TableColumnsButton`（ConsumerWidget）：
   - 仅在当前 page 的 `ViewMode.table` 时显示（或常驻但仅对表格有效）。
   - 读取/写入本地 `table_columns:<pageKey>`。
   - 打开 bottom sheet 展示列勾选 UI。
4. 筛选/排序交互：
   - 列标题内嵌图标按钮（filter/sort）。
   - filter 点击弹出 BottomSheet，包含操作符选择与输入框。
   - sort 为三态切换：无排序 / 升序 / 降序。

### 状态与持久化
- 新增 provider：`tableColumnsOverrideProvider.family<AsyncValue<List<String>?>, String>(pageKey)`
  - read：StorageService `table_columns:<pageKey>`
  - write：同 key
- 解析逻辑（最终生效列 keys）：
  1. `uiConfig.tableColumns`（来自远端/缓存/assets）作为默认。
  2. 若本地 override 存在，则用 override 覆盖默认（取交集过滤未知 key）。
  3. 应用冻结逻辑：冻结“最终 keys”的首列。

## 风险与回退
- 自定义冻结表格实现复杂度高：若出现性能问题，先限制 rows 渲染上限或在 rows 超过阈值时回退到非冻结 `DataTable`。
- 保持兼容：不改变 JSON schema 必填字段，仅新增可选能力与本地覆盖。
