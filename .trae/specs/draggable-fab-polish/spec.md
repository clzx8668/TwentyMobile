# 可拖动 FAB 动效与细节优化 Spec

## Why
当前 DraggableFab 的核心能力（可见、可拖动、跨页共享、贴边吸附、peek/唤醒）已满足主需求，但动效观感偏“硬”、peek 露出宽度偏大，导致整体精致度不足。

## Goals
- 动画更细腻：吸附、peek、唤醒的运动更平滑、减速更自然。
- peek 更克制：靠边停靠后自动半隐藏时露出更少，但仍易于点击唤醒。
- 行为一致：四个主页面切换时视觉一致、无跳跃感；拖动与点击命中保持正确。

## Non-Goals
- 不改变位置持久化语义（继续保持全局 side + yFraction）。
- 不引入新的全局 UI 入口或路由级重构。

## What Changes
1) **吸附/peek/唤醒的动画曲线与物理感**
   - 将当前的固定时长 + curve 动画升级为更自然的 spring（或等价的 easing 组合），分别为：
     - Snap（贴边吸附）
     - Peek（进入半隐藏）
     - Wake（从半隐藏唤醒）
   - 允许分别配置动画参数（例如：duration / curve 或 spring 参数），并提供默认值。

2) **peek 呈现方式从“平移出屏”改为“裁剪显示”**
   - 目前 peek 通过把 FAB 的 x 位置平移到屏幕外，仅露出 `peekWidth`，导致可点击区域也只有露出的那一小条。
   - 改为：保持 FAB 的 positioned 坐标仍贴边（不出屏），但使用裁剪（ClipRect/Align）只显示一小条“peek strip”。
   - 好处：
     - 露出可以更少，但点击/唤醒仍然容易（命中区域可保持更大）。
     - 避免边缘裁剪/坐标系差异导致的偶发不可见风险。

3) **默认参数微调**
   - 将默认 peek 露出宽度调小（例如 22 → 12~16 区间，以最终体验为准）。
   - 为 peek 状态提供最小可点击宽度/命中兜底（例如命中区域至少 40px 宽，视觉只露出 12~16px）。

## Acceptance Criteria
### Requirement: 动画细腻
- **WHEN** 用户长按拖动结束并靠近左右边缘释放
- **THEN** FAB 以更自然的减速/回弹感吸附到边缘（无“突然停住/突兀跳动”）
- **AND** 吸附动画不会影响点击命中（动画结束前后均可正常点击/拖动）

### Requirement: peek 露出更少但易唤醒
- **WHEN** FAB 自动进入 peek
- **THEN** 视觉露出宽度小于当前版本（目标：12~16px）
- **AND** 用户点击露出区域可稳定唤醒回完全可见贴边状态（无需非常精准点击）

### Requirement: 跨页一致
- **WHEN** 用户在任一主页面拖动 FAB 改变位置
- **THEN** 切换到其他主页面 FAB 位置/形态/动效保持一致（无明显跳跃感）

## Impacted Code
- `lib/presentation/shared/draggable_fab.dart`
- `lib/presentation/home/today_screen.dart`（仅使用方参数对齐，如需要）

