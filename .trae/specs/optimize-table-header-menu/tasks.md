# Tasks
- [x] Task 1: 调整列标题默认展示（移除常驻筛选/排序按钮）
  - [x] 识别现有列标题渲染中筛选/排序按钮与点击排序入口
  - [x] 改为标题区域可点击（InkWell/GestureDetector），并保留必要的可访问性语义

- [x] Task 2: 实现 Twenty 风格二级菜单（上下文菜单 + 排序子菜单）
  - [x] 菜单项：过滤、排序、右移、左移、隐藏（按列能力与边界条件动态显示/禁用）
  - [x] 排序子菜单：升序、降序、清除
  - [x] 锚定策略：优先就近锚定到列标题区域；若锚定失败则使用现有弹窗兜底

- [x] Task 3: 接入现有能力（筛选/排序/列顺序/列可见性持久化）
  - [x] “过滤”复用现有列筛选面板（含 op 选择）
  - [x] “排序”复用现有排序状态与数据刷新逻辑
  - [x] “移动/隐藏”复用列配置与持久化键，保持与列配置面板一致
  - [x] 最小可见列数约束：隐藏导致低于阈值时阻止并提示

- [x] Task 4: 状态指示（低噪音）
  - [x] 已筛选列：标题展示小点/徽标
  - [x] 已排序列：标题展示方向箭头

- [x] Task 5: 验证与回归
  - [x] 单元/Widget 测试：点击列标题可弹出菜单；选择“过滤/排序”能触发对应行为
  - [x] 回归记录（2026-04-21）：
    - flutter test：通过
    - flutter build apk --debug：通过（build/app/outputs/flutter-apk/app-debug.apk）
    - flutter build windows --debug：sentry-native 依赖拉取受网络影响失败（与本改动无关）

# Task Dependencies
- Task 2 depends on Task 1
- Task 3 depends on Task 2
- Task 4 depends on Task 1
- Task 5 depends on Task 3
