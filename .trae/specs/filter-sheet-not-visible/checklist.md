# 验收清单：筛选弹窗不显示（仅遮罩）

- [ ] Android 真机（Debug）点击任意可筛选列的筛选图标，BottomSheet 必定可见（不出现仅遮罩）
- [ ] 连续快速点击筛选 20 次无红屏、无遮罩残留、无状态卡死
- [ ] 键盘弹出/收起、表格滚动中点击筛选，BottomSheet 仍可见且内容可操作
- [ ] Debug 日志可检索并包含：open-start / open-builder / open-end（含列 key、context 来源、insets、结果与耗时）
- [ ] 发生异常时日志包含异常信息与堆栈（Debug Only），便于定位根因

