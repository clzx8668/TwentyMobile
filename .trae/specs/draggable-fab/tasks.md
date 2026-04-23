# Tasks
- [x] Task 1: 盘点与统一入口
  - [x] 扫描所有页面的 Scaffold `floatingActionButton` 使用点（包含 JSON 渲染页面的创建入口）
  - [x] 定义页面标识策略（优先 route/pageKey；无则使用 widget 名称 + 业务 key）

- [x] Task 2: 实现可复用 DraggableFab 容器
  - [x] 交互：长按进入拖动，松手吸附左右边缘，不触发 onPressed
  - [x] 约束：SafeArea 边界限制 + 边距 + 屏幕尺寸变化自修正
  - [x] 视觉：拖动时提升层级（overlay/stack），与现有主题一致

- [x] Task 3: 位置存储与恢复
  - [x] 使用现有 StorageService 写入/读取位置（按页面 key）
  - [x] 设计存储格式（例如 {dx, dy, side} 或归一化坐标），支持不同分辨率/横竖屏
  - [x] 提供清除位置接口（用于“恢复默认位置”）

- [x] Task 4: 接入各页面
  - [x] 将需要 FAB 的页面替换为 DraggableFab 包裹（保持按钮样式与原行为不变）
  - [x] 对不需要 FAB 的页面不做改动

- [x] Task 5: 测试与回归
  - [x] Widget 测试：长按拖动后位置变化；松手吸附；重新 pump 后位置恢复（使用 fake StorageService）
  - [x] 真机回归：至少验证 Contacts/Companies/Tasks/Home 等核心页面，拖动不遮挡且无红屏

# Task Dependencies
- Task 2 depends on Task 1
- Task 3 depends on Task 2
- Task 4 depends on Task 2
- Task 5 depends on Task 4
