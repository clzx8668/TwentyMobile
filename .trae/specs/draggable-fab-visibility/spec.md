# 可拖动 FAB 显示修复 Spec

## Why
当前四个主页面（Contacts/Companies/Tasks/Home）出现 FAB 入口“看不见”的问题，严重影响核心操作可发现性与可用性。

## What Changes
- 调整 DraggableFab 的“半隐藏（peek）”恢复策略：默认进入页面时必须处于完全可见贴边状态，避免首次进入/切换页面时仅露出极小边缘导致用户误以为 FAB 消失。
- 调整持久化数据语义：不再把 `peeked` 作为可恢复状态（或解码时忽略），peek 仅作为短时交互态，由定时器触发。
- 当检测到历史数据导致 FAB 在边缘露出不足以辨识时，自动唤醒到完全可见贴边状态，并延迟进入 peek。
- **BREAKING**：`draggable_fab:pos:global` 的持久化字段语义变更（`peek` 不再作为恢复来源）。

## Impact
- Affected specs: 可拖动 FAB（跨页面共享、贴边吸附、半隐藏与唤醒）
- Affected code: `lib/presentation/shared/draggable_fab.dart`；四个页面的 FAB 接入点无需变更

## ADDED Requirements
### Requirement: 默认可见
系统 SHALL 在进入任意带 DraggableFab 的页面时，首先以“完全可见贴边状态”展示 FAB。

#### Scenario: 页面首次打开
- **WHEN** 用户进入 Contacts/Companies/Tasks/Home 任意页面
- **THEN** FAB 以可辨识的完整按钮形式出现（不处于 peek 半隐藏）
- **AND** 在 `peekDelay` 到期后才允许自动进入 peek

### Requirement: peek 不作为恢复态
系统 SHALL 将 peek 视为临时交互态，不作为持久化恢复状态来源。

#### Scenario: 重启/切换页面
- **WHEN** 用户重启应用或从 A 页面切换到 B 页面
- **THEN** FAB 的边缘吸附侧与纵向相对位置保持一致
- **AND** FAB 初始处于完全可见贴边状态

## MODIFIED Requirements
### Requirement: 贴边半隐藏与唤醒
系统 SHALL 支持贴边吸附与半隐藏（peek），并在用户点击半隐藏区域后唤醒回完全可见贴边状态；且“默认可见”优先级高于历史 peek 状态。

## REMOVED Requirements
### Requirement: peek 状态可持久化恢复
**Reason**: peek 仅露出很窄边缘，易被误认为按钮消失；作为恢复态会降低可发现性。
**Migration**: 读取到旧数据时忽略 `peek` 字段或强制设置为 `false`；必要时对明显不可见的位置执行自动唤醒并重写持久化数据。

