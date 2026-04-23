# Tasks
- [x] Task 1: 调整 DraggableFab 的恢复策略为“默认可见”
  - [x] 解码持久化数据时忽略 peek 字段（或将其迁移为 false）
  - [x] 进入页面/路由变更时保证 FAB 处于完全可见贴边状态，并重新调度 peek
  - [x] 对历史数据导致“露出过小”的场景执行自动唤醒并持久化修正

- [x] Task 2: 回归测试与真机验证
  - [x] Widget 测试：当存储中的 peek=true 时，进入页面仍应显示完全可见贴边 FAB
  - [x] Widget 测试：peekDelay 到期后进入 peek；点击可唤醒回完全可见
  - [x] 真机回归：Contacts/Companies/Tasks/Home 四页均可见，且不出现“看不见”的情况

# Task Dependencies
- Task 2 depends on Task 1
