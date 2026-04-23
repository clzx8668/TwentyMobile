# 可拖动浮动 FAB Spec

## Why
当前多个页面的右下角 FAB 固定在默认位置，容易遮挡关键内容（例如列表底部、输入框或 BottomSheet），影响操作与可读性。

## What Changes
- 将各页面的“添加”FAB 改为可浮动并支持长按拖动移动位置
- FAB 位置按页面维度持久化（重启后仍保持用户设置）
- 提供吸附与边界限制：避免拖出屏幕/安全区域，松手后吸附到左右边缘
- 提供恢复默认位置能力（可从页面菜单/设置入口触发）

## Impact
- Affected specs: 页面级创建入口（Add/Create）、可用性/可访问性
- Affected code: 各页面 Scaffold 的 `floatingActionButton` 组装、存储服务（StorageService/Hive fallback）、路由/页面标识

## ADDED Requirements
### Requirement: 可拖动 FAB
系统 SHALL 支持用户通过长按拖动来移动 FAB，并在松手后将 FAB 停留在用户选择的位置。

#### Scenario: 长按进入拖动模式
- **WHEN** 用户长按 FAB
- **THEN** 进入拖动模式，FAB 可被拖动
- **AND** 不触发 FAB 的 onPressed

#### Scenario: 拖动与边界限制
- **WHEN** 用户拖动 FAB
- **THEN** FAB 的移动被限制在页面可视区域内
- **AND** 避免与系统安全区域冲突（状态栏、底部手势区、导航栏）

#### Scenario: 松手吸附
- **WHEN** 用户松手结束拖动
- **THEN** FAB 自动吸附到最近的左右边缘
- **AND** 保持合理的边距（例如 12–16dp）

### Requirement: 位置持久化（按页面）
系统 SHALL 按页面维度保存 FAB 位置，用户下次进入同一页面时恢复上次位置。

#### Scenario: 首次进入页面
- **WHEN** 用户首次进入页面且无保存位置
- **THEN** FAB 显示在默认位置（右下角，遵循 SafeArea）

#### Scenario: 已保存位置恢复
- **WHEN** 用户进入页面且存在保存位置
- **THEN** FAB 显示在保存位置（若超出边界则自动修正）

### Requirement: 恢复默认位置
系统 SHALL 提供恢复默认 FAB 位置的入口。

#### Scenario: 恢复默认
- **WHEN** 用户触发“恢复默认位置”
- **THEN** 清除该页面保存的 FAB 位置并立即回到默认位置

## MODIFIED Requirements
### Requirement: 页面 FAB 放置策略
系统 SHALL 仅在需要“创建/添加”快捷入口的页面展示 FAB；展示时默认可拖动且不遮挡核心内容。

## REMOVED Requirements
### Requirement: 固定右下角 FAB
**Reason**: 固定位置容易遮挡内容，且在不同设备/字号/横竖屏下不可控。
**Migration**: 由可拖动 FAB 替代；默认仍从右下角出现，但允许用户调整与持久化。

