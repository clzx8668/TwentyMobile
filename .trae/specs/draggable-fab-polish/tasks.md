# Tasks
- [ ] Task 1: 动画参数与实现升级
  - [ ] 为 snap/peek/wake 拆分动画配置（duration/curve 或 spring 参数）
  - [ ] 将吸附/peek/唤醒的移动动画替换为更细腻的实现（优先 spring）

- [ ] Task 2: peek 改为裁剪呈现 + 命中兜底
  - [ ] peek 状态不再通过 x 平移出屏；改为贴边位置 + ClipRect/Align 裁剪露出
  - [ ] 保持/提升 peek 状态可点击唤醒的命中面积（避免只剩一条细线难点中）
  - [ ] 调小默认 peek 露出宽度（目标 12~16px）

- [ ] Task 3: 回归测试与真机验证
  - [ ] Widget 测试：peek 露出更小但仍可点击唤醒
  - [ ] Widget 测试：拖动释放后的吸附动画结束位置正确（左右贴边、yFraction 持久化）
  - [ ] 真机回归：Home/Contacts/Companies/Tasks 四页切换无跳跃感，动效更顺滑

# Task Dependencies
- Task 3 depends on Task 1 and Task 2
