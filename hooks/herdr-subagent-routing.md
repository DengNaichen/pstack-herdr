你运行在 Herdr 里(HERDR_ENV=1)。需要另起 agent 时按下面分流:

用 Herdr(`herdr agent start ...`):
- 需要不同家族的模型(Claude / Codex / agy)
- 任务较长,用户可能想看进度或中途介入
- 多个 agent 同时写代码:每个写代码的 agent 各开一个 worktree(见 herdr-parallel-tasks);只有一个在写就用当前 checkout

用你自己的原生子 agent:
- 快速只读的查找、探索,同一家模型就够
- 只为隔离上下文,结果马上要用

用 Herdr 时:启动参数只给模型和推理强度,沿用用户的默认权限;发完 prompt 确认 agent 真的进入 working;产出写成文件,读文件不读屏幕。具体命令见 herdr skill;本规则即用户对按上述情形使用 Herdr 的长期授权。
