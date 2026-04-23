# Tasks
- [x] Task 1: 修复点击命中（拖动后可点击、不穿透）
  - [x] 调整 DraggableFab 位移实现，使命中区域随位置移动（避免仅 paint translate）
  - [x] 回归：拖动后点击 FAB 仍触发 onPressed，且下方控件不响应

- [x] Task 2: 全局共享位置（跨页面一致）
  - [x] 定义全局存储 key（例如 `draggable_fab:pos:global`），替代按 pageKey
  - [x] 将存储格式改为可跨页面映射的值（推荐全局坐标 topLeft，或归一化坐标）
  - [x] 在 DraggableFab 内实现“读取共享位置→根据当前页面 base 计算实际渲染位置”的映射

- [x] Task 3: 贴边半隐藏与唤醒
  - [x] 吸附策略：松手后贴边；支持进入半隐藏（peekWidth）
  - [x] 唤醒策略：半隐藏状态点击时动画回到完全可见贴边位置
  - [x] 持久化：半隐藏/可见两态均应可恢复，并确保可被唤醒

- [x] Task 4: 接入与迁移
  - [x] 确认各页面 DraggableFab 接入无需逐个改动（默认走全局共享）
  - [x] 兼容旧按页面存储数据：首次读取时迁移到全局 key（或直接忽略并重置）

- [x] Task 5: 测试与真机回归
  - [x] Widget 测试：拖动后点击命中；共享位置在不同页面实例间一致
  - [x] 集成测试：Android 上拖动→半隐藏→点击唤醒→切换/重建后恢复
  - [x] 真机回归：Contacts/Companies/Tasks/Home 页面验证不遮挡、可点击、位置一致

# Task Dependencies
- Task 2 depends on Task 1
- Task 3 depends on Task 1
- Task 4 depends on Task 2
- Task 5 depends on Task 3
