# 可拖动 FAB 细节优化 Spec

## Why
当前可拖动 FAB 已可移动与持久化，但存在交互与一致性问题：移动后点击命中异常、不同页面位置不一致导致切换跳动、贴边吸附与“半隐藏/唤醒”体验不完善。

## What Changes
- 修复：FAB 拖动后仍可正常点击触发（命中区域与视觉位置一致，不穿透到底层控件）
- 改为全局共享位置：任一页面拖动 FAB，会同步影响其他页面的基础位置，保持跨页面一致
- 优化贴边吸附与“半隐藏/唤醒”：
  - 拖到左右边缘可吸附并允许半隐藏（露出一小段）
  - 点击半隐藏 FAB 可“唤醒”回到完全可点击状态

## Impact
- Affected specs: 可拖动 FAB（draggable-fab）
- Affected code: `DraggableFab` 组件、FAB 位置存储键、各页面接入参数（pageKey/共享 key）、测试用例

## ADDED Requirements
### Requirement: 点击命中一致
系统 SHALL 保证 FAB 的点击命中区域与视觉位置一致，拖动后点击 FAB 仍触发原有 `onPressed`，不得穿透到其下方控件。

#### Scenario: 拖动后点击
- **WHEN** 用户长按拖动 FAB 到新位置并松手
- **THEN** 用户点击 FAB
- **AND** 触发 FAB 原有 onPressed 行为
- **AND** 不触发 FAB 下方控件的点击

### Requirement: 跨页面共享位置
系统 SHALL 将 FAB 位置作为“全局共享基础位置”，任一页面调整后，其他页面进入/返回时保持一致，减少跳动感。

#### Scenario: 页面间同步
- **WHEN** 用户在页面 A 拖动并松手
- **THEN** 页面 B（同一应用会话内）进入时 FAB 位置与页面 A 一致（在允许边界内自动修正）

#### Scenario: 持久化恢复（共享）
- **WHEN** 用户重启应用后进入任一页面
- **THEN** FAB 恢复到上次共享位置（若越界则自动修正）

### Requirement: 贴边半隐藏与唤醒
系统 SHALL 支持 FAB 在左右边缘吸附后进入半隐藏状态，并支持通过点击唤醒回完全可见/可点击状态。

#### Scenario: 贴边吸附进入半隐藏
- **WHEN** 用户将 FAB 拖到屏幕左/右边缘并松手
- **THEN** FAB 自动吸附到最近边缘
- **AND** 可处于半隐藏状态（仅露出固定宽度，例如 12–16dp）

#### Scenario: 点击唤醒
- **WHEN** FAB 处于半隐藏状态
- **THEN** 用户点击 FAB
- **AND** FAB 动画回到完全可见位置（仍贴边）

## MODIFIED Requirements
### Requirement: 位置存储格式
系统 SHALL 将持久化位置从“按页面 delta”调整为“全局共享位置”（推荐存储全局坐标或可跨页面映射的归一化坐标），以实现一致性。

## REMOVED Requirements
### Requirement: 按页面维度存储 FAB 位置
**Reason**: 会导致不同页面 base offset 不一致，切换页面出现跳动。
**Migration**: 改为全局共享位置存储；如需差异化可后续引入可选 groupKey。

