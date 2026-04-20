# 任务分解（Table View Enhancements）

## 阶段 0：现状确认
- [x] 定位灰色文本来源：`TableView`/`DataTableTheme`/cellBuilder TextStyle
- [x] 确认表格在各页面的承载容器是否提供垂直滚动（RefreshIndicator 触发条件）

## 阶段 1：颜色修复
- [x] 在 `TableView` 层统一设置 `DataTable` 的 `dataTextStyle`/`headingTextStyle`，确保使用 `colorScheme.onSurface`
- [x] 空态文案保持较淡（onSurface 60%）
- [x] 真机浅色/深色主题各验证一次

## 阶段 2：列显示/隐藏（本地持久化）
- [x] 定义 storage key：`table_columns:<pageKey>`
- [x] 新增 provider/notifier：读写列 override（List<String>）
- [x] 新增 UI 按钮：表格模式右上角 `TableColumnsButton(pageKey)`
- [x] BottomSheet：列列表 + 勾选 + 应用/重置（重置回到 UI config 默认）
- [x] 规则：至少 2 列可见；未知列 key 自动过滤
- [x] 接入 JSON 渲染：`entity_list` 与 `home_today` 的表格都使用“最终列 keys”

## 阶段 3：冻结首列 + 压缩列宽
- [x] 扩展 `TableColumnDef` 支持宽度提示（例如 width/min/max）
- [x] 实现 `FrozenTableView<T>`：
  - [x] 左右两侧拆分 columns
  - [x] 两个垂直 ScrollController 同步
  - [x] 右侧外层横向 SingleChildScrollView
  - [x] Header 与 rows 对齐
  - [x] Text overflow: ellipsis
- [x] 默认冻结列数：1（仅在 columns > 1 时启用）
- [x] 默认宽度建议：
  - contacts：name=160，company=140
  - companies：name=180，domain=160
  - tasks：title=200，status=110
- [x] 大数据量回退策略（可选）：rows 超阈值时退回 `DataTable`（避免一次性渲染过多）

## 阶段 4：真机回归
- [x] 四个主页面：表格/列表切换正常
- [x] 表格：右上角列配置按钮可用、重启后生效
- [x] 表格：横向滚动时首列固定不动
- [x] 表格：纵向滚动左右两侧不错行

## 阶段 5：筛选/排序/分页与列顺序
- [x] 扩展 `TableColumnDef`：增加可排序/可筛选的数据提取器（如字符串值 getter）
- [x] `TableView` 增加筛选与排序状态（支持所有可见字段）
- [x] `TableView` 底部增加分页与汇总栏（总数、区间、页码、每页条数、跳页）
- [x] 列配置面板新增列顺序调整（拖拽重排）并复用现有持久化
- [x] JSON 渲染入口无需改 schema，保持与现有 `tableColumns` 兼容
- [x] 真机回归：筛选/排序/分页/跳页/列顺序在 contacts/companies/tasks/home 表格可用

## 阶段 7：筛选弹窗升级（BottomSheet + 操作符）
- [x] 将列筛选从对话框改为 BottomSheet，并提供操作符选择（contains/equals/startsWith）
- [x] 更新筛选状态结构：每列保存 {op, value}，支持多列叠加（AND）
- [x] UI：Apply/Clear/Cancel；筛选图标展示“已启用”状态
- [x] 真机回归：Contacts/Companies/Tasks/Home 表格均可筛选并切换操作符

## 阶段 8：Twenty 对齐修整（筛选稳定性 + 冻结选择列）
- [x] 修复筛选点击仅弹键盘但 BottomSheet 不显示的问题（消除红屏布局异常）
- [x] 冻结首列改为“选择列”：窄宽（checkbox + icon），对齐 Twenty
- [x] 为 contacts/companies/tasks 提供默认图标（或首字母圆形图标）
- [x] 表格选择逻辑与分页/筛选/排序协同：切页后 selection 行为明确（保留或清除需一致）
- [x] 真机回归：快速点击筛选 10 次无红屏；横向滚动冻结列为窄选择列

## 阶段 6：验收失败项修复/补证
- [x] 修复冻结列数量不一致：已按最新需求统一为 `frozenColumnCount=1`，并同步规格与验收清单
- [x] 补齐 Android 真机回归（首页）：验证首页表格/列表切换
- [x] 补齐 Android 真机回归（Contacts/Companies/Tasks）：逐页验证表格/列表切换
- [x] 补齐 Android 真机稳定性回归：验证“切换列显示”全流程无红屏/崩溃
