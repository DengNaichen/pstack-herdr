# pstack-herdr

[poteto/pstack](https://github.com/poteto/plugins/tree/main/pstack) 的个人改编版,适配在 Herdr 里跑多家模型(Claude / Codex / Antigravity)的环境。

原作 MIT 许可,见 [LICENSE](LICENSE)。

## 内容

| skill | 调用方式 | 相对上游的改动 |
| --- | --- | --- |
| `arena` | `/arena` 手动 | 重写:只做方案;任一 agent 主持,多家模型经 Herdr 起在 2×2 tab 里;匿名评审 |
| `architect` | `/architect` 手动 | 模型用 arena 的表 |
| `how` | 自动可见 | 探索/讲解用本工具的只读子 agent;批评模式经 Herdr 起多家模型 |
| `why` | 自动可见 | 调查/综合用本工具带 MCP 的子 agent;列出本会话的 MCP |
| `figure-it-out` | `/figure-it-out` 手动 | 去掉对 poteto-mode 的依赖 |
| `show-me-your-work` | `/show-me-your-work` 手动 | 交叉审查改用 Herdr 起别家模型;不读 Cursor 的 transcript 目录 |
| `herdr-parallel-tasks` | 自动可见 | 自己写的(非 pstack,原 herdr-ticket-flow);不绑 ticket/issue;多个 agent 同时写代码才开 worktree,仓库有入口时先用入口建再 `herdr worktree open` 挂进侧边栏 |
| `principle-*`(20 条) | 自动可见 | 去掉 `disable-model-invocation`,description 常驻作为原则索引 |

## 安装

把本仓库克隆到任意位置(下文记作 `<clone>`)。`~/.agents/skills/` 是中心,其他工具的目录都链接到它:

```text
~/.agents/skills/<skill>         -> <clone>/skills/<skill>                     (Codex 直接读)
~/.claude/skills/<skill>         -> ../../.agents/skills/<skill>              (Claude Code)
~/.gemini/config/skills/<skill>  -> ~/.agents/skills/<skill>                  (Antigravity / agy)
```

## Hooks

`hooks/herdr-subagent-routing.sh` 是 SessionStart hook:在 Herdr 里(`HERDR_ENV=1`)把 [`herdr-subagent-routing.md`](hooks/herdr-subagent-routing.md) 的分流规则注入上下文,告诉 agent 什么时候用 Herdr 起 agent、什么时候用原生子 agent;不在 Herdr 里不注入。规则正文只改这一个 md。

安装:`~/.agents/hooks -> <clone>/hooks`,三家的全局配置各加一条(与 Herdr 自带的 hook 并列,不改它们):

| 工具 | 配置文件 | 命令 |
| --- | --- | --- |
| Claude Code | `~/.claude/settings.json` → `hooks.SessionStart`,matcher `^(startup\|clear\|compact)$` | `sh ~/.agents/hooks/herdr-subagent-routing.sh claude` |
| Codex | `~/.codex/hooks.json` → `hooks.SessionStart`;首次需在 Codex 交互界面信任 | `sh ~/.agents/hooks/herdr-subagent-routing.sh codex` |
| agy | `~/.gemini/config/hooks.json` → `herdr-subagent-routing.SessionStart` | `sh ~/.agents/hooks/herdr-subagent-routing.sh agy` |
