# Tasks
- [x] Task 1: 复现路径与诊断点对齐
  - [x] 收集真机复现步骤（建议优先在 TableView 筛选入口复现）
    - 打开包含表格的页面（TableView），进入任意列表（如 companies/tasks 等表格页）
    - 触发筛选：点击某一列的筛选按钮（记录列 key/label）
    - 触发条件组合（逐个验证并记录是否复现）：
      - 列表正在滚动中点击筛选（手指未离开/惯性滚动中）
      - 键盘弹出状态下点击筛选（先点击搜索框/输入框使键盘出现）
      - 刚完成 setState/刷新后立刻点击筛选（如切换视图模式/切换列/刷新数据后）
      - 连续快速点击筛选 5–10 次
    - 现象记录：
      - 是否出现遮罩但 BottomSheet 内容不可见
      - 是否完全无遮罩/无弹窗
      - 是否出现一次后后续都无法打开（卡死/防重入未释放）
  - [x] 明确预期日志字段与输出位置（Debug logcat/grep 可检索）
    - 关键字（grep/logcat 过滤用）：
      - `TableView: openFilterSheet start`
      - `TableView: openFilterSheet context`
      - `TableView: openFilterSheet done`
      - `TableView: openFilterSheet error`
      - `TableView: openFilterSheet end`
      - `ColumnFilterSheet: build`
      - `showModalBottomSheet completed without entering builder`
    - 期望一次完整打开至少包含：
      - start（带 column.key）
      - context（primary/fallback 来源与 elapsedMs）
      - done（source、builderEntered、action、elapsedMs）
      - end（elapsedMs）

- [x] Task 2: 调试日志与异常捕获（Debug Only）
  - [x] 将关键诊断日志从 `assert(debugPrint...)` 调整为 `kDebugMode` 条件日志（确保 Debug 真机必定可见）
  - [x] 为 showModalBottomSheet 打开流程增加耗时统计与结果日志（apply/clear/cancel）
  - [x] 捕获并记录弹窗打开过程中的同步/异步异常（含堆栈）

- [x] Task 3: 弹窗打开策略与回退实现
  - [x] 主策略：使用 root navigator overlay context 打开 BottomSheet（避免局部 context/约束问题）
  - [x] 回退策略：若主策略未进入 builder 或抛异常，则切换为另一种 context 来源再次尝试（最多一次）
  - [x] 防重入：保留并验证快速连点不会导致遮罩残留或状态卡死

- [ ] Task 4: 真机验证与回归
  - [ ] 真机 Debug：连续点击筛选 20 次，确保每次都有可见 BottomSheet
  - [ ] 真机 Debug：键盘弹出/收起、滚动中点击筛选，BottomSheet 仍可见且内容可滚动
  - [ ] 验证日志：一次打开动作能完整输出 start/builder/end 三段日志

# Task Dependencies
- Task 4 depends on Task 2
- Task 3 depends on Task 2
