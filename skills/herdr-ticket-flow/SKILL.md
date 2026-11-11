---
name: herdr-ticket-flow
description: "一张 ticket 一个 worktree workspace、一个 agent 从头干到尾。当用户交来一个或多个 ticket / issue(如 ENG-123)要你实现,或要求「开个 worktree / 分支」「这几件事并行做」「把这个 ticket 干完」时使用。要求 HERDR_ENV=1;否则停下来说明。"
---

# Herdr 的 ticket 流程

## 前提

```bash
test "${HERDR_ENV:-}" = 1
```

不满足就停下来,直接说「我不在 Herdr 的 pane 里,这套流程需要它」,不要用裸 git 命令硬凑。

## 单位是 ticket,不是任务

一张 ticket 由**一个 agent 从头干完**。不要因为「可以并行」就把一张 ticket 拆成两个 agent —— 并行发生在 **ticket 之间**,不在 ticket 内部。

## 铁律:拓扑先建,agent 后起

agent 的 cwd 在进程启动那一刻钉死,之后**没有任何办法改**。所以:

- 永远不要「先起 agent,再让它进 worktree」;
- 永远不要让 agent 用 `git -C` 去别人的 checkout 里干活;
- 永远不要用裸 `git worktree add`。

**一张 ticket = 三步:**

```bash
# 1) 建拓扑。返回的 root pane 已经站在这个 checkout 里。
herdr worktree create --cwd <repo-root> --branch <ticket>-<slug> \
    --label <TICKET> --no-focus
#    → 解析 .result.workspace.workspace_id 和 .result.root_pane.pane_id

# 2) 在那个 pane 里起 worker
herdr agent start <ticket小写> --kind <kind> --pane <root_pane.pane_id>

# 3) 派活并等它落地
herdr agent prompt <ticket小写> "<ticket 正文 + 验收条件>" --wait --timeout 900000
```

## 命名:一个名字贯穿四个表面

| 表面 | 值 |
| --- | --- |
| Linear | `ENG-123` |
| workspace label | `--label ENG-123` |
| branch | `--branch eng-123-fix-login` |
| agent 名 | `eng-123` |

agent 名必须匹配 `[a-z][a-z0-9_-]{0,31}` 且在 session 内唯一。这样 `herdr agent prompt eng-123 "..."` 不用查 pane id,侧边栏第一行就是 ticket 号。

## 硬性要求

- **永远带 `--no-focus`** —— 不能抢用户的焦点,一次都不行。
- **所有改动只发生在该 ticket 的 worktree 里。** 不要在主 checkout 或别人的 worktree 里动手。
- **不要猜 id。** 并行创建时 id 不保证有序(实测 `w6, w8, w7, w9`),一律从 JSON 解析。
- **`--trust-repository` 只在用户确认过该仓库后才用**,它不是失败重试开关。
- **信息不全就停下来问**:拿不到 ticket 正文、repo root 不确定、用哪个 agent kind 不知道。

## 读 worker 的输出

- 状态汇总:`herdr agent list`。
- 读屏幕必须用 `--source visible`。pi 等 TUI 走 alternate screen,`recent-unwrapped` 读回来是空白。
- **不要把状态当完成信号。** Antigravity、Grok 一回到提示符就算 `idle`,后台任务可能还在跑;`agent wait` 观察的是 agent 状态,不是任务完成。

## 回报:让 worker 写文件,别抓屏幕

每个 worker 结束时写 `<worktree>/.herdr-report.md`:做了什么、改了哪些文件、怎么验证、还剩什么。

主 agent 汇总这些文件回报给用户 —— 不要去翻 N 个 pane 的屏幕。

## 收尾

- **不要自己删 worktree。** PR 合并后由用户发起,或经用户明确确认。
- `herdr worktree remove --workspace <id>` 删 checkout、**保留分支**;`herdr workspace close` 只关 Herdr 状态、不碰 git。两条路别混。
- 关闭带子 worktree 的主 workspace 要带 `--group`,否则返回 `workspace_group_close_required`。

## 边界

Herdr 只负责**拓扑**:checkout、pane、agent 的位置。分支、commit、PR、合并后删分支,都是 git 的事。不要用 Herdr 的命令去动 git 历史。

## 主会话的位置

用户通常有一个常驻会话在**主分支**上。那是调度台:自己不碰代码,只建拓扑、派工、汇总。

它永远待在 main —— 这样侧边栏的 `branch` 列永远不会说谎,因为没有任何 agent 在自己的 workspace checkout 之外干活。

## 反模式速查

| 反模式 | 为什么错 |
| --- | --- |
| `git worktree add` + `cd` 进去干活 | 侧边栏看不见,而且 cwd 改不掉 |
| 主会话里用内部 subagent 干 ticket | 没有 pane,就没有屏幕可跳、没有 `blocked` 可看 |
| `herdr pane move` 搬自己的 pane | 不带 cwd,搬完标签是新的、分支还是旧的,布局开始说谎 |
| 一张 ticket 拆给两个 agent | 并行粒度错了,合并成本远大于收益 |
