---
name: herdr-parallel-tasks
description: "在 Herdr 里把几件独立的事分派给 agent 并行完成:一件事一个 agent 从头做到尾;同时有不止一个 agent 写代码时,每个各开一个 worktree workspace。用于用户要求「这几件事并行做」「派几个 agent 分别去做」。要求 HERDR_ENV=1;否则停下来说明。"
---

# Herdr 并行分派任务

## 前提

```bash
test "${HERDR_ENV:-}" = 1
```

不满足就停下来,直接说「我不在 Herdr 的 pane 里,这套流程需要它」,不要用裸 git 命令硬凑。

## 什么时候开 worktree

**同一时间有不止一个 agent 会写代码,才给每个写代码的 agent 各开一个 worktree。** 只有一个在写,就用当前 checkout。

- 派出去一个 agent,主会话同时也在改代码 —— 两个在写,开。
- 派出去一个 agent,主会话只调度不写 —— 一个在写,不开;在当前 workspace 切一个 pane 起它即可。
- 只读的调查、方案、评审 —— 不写代码,不开。

仓库自己的 `AGENTS.md` / git 流程另有规定时,以仓库为准。

## 单位是一件独立交付

一件事由**一个 agent 从头做完**。不要因为「可以并行」就把一件事拆给两个 agent —— 并行发生在**事与事之间**,不在一件事内部。

## 铁律:拓扑先建,agent 后起

agent 的 cwd 在进程启动那一刻钉死,之后**没有任何办法改**。所以:

- 永远不要「先起 agent,再让它进 worktree」;
- 永远不要让 agent 用 `git -C` 去别人的 checkout 里干活;
- 不要用裸 `git worktree add` 自己建 checkout:用仓库的 worktree 入口或 `herdr worktree create`(见下),并且一定挂进 Herdr,侧边栏才看得到。

**需要 worktree 的一件事 = 三步。** 第 1 步有两条路,先看仓库有没有自己的 worktree 入口(读仓库的 `AGENTS.md` / git 流程文档,例如 Stet 的 `scripts/new-worktree`):

```bash
# 1a) 仓库有入口:用它建(保留它的路径约定、基线刷新和环境准备),再挂进 Herdr
<repo-root>/scripts/new-worktree <branch>          # 以仓库文档为准;输出新 checkout 的路径
herdr worktree open --cwd <repo-root> --path <新 checkout 路径> \
    --label <name> --no-focus

# 1b) 仓库没有入口:直接让 Herdr 建
herdr worktree create --cwd <repo-root> --branch <branch> \
    --label <name> --no-focus

#    两条路都解析 .result.root_pane.pane_id(和 workspace id);root pane 已经站在这个 checkout 里。

# 2) 在那个 pane 里起 worker
herdr agent start <name> --kind <kind> --pane <root_pane.pane_id>

# 3) 派活并等它落地
herdr agent prompt <name> "<任务描述 + 验收条件>" --wait --timeout 900000
```

不需要 worktree 时,跳过第 1 步:在当前 workspace 切一个 pane(`herdr pane split --current ... --no-focus`),再做第 2、3 步。

## 命名:一个名字贯穿各个表面

每件事取一个短名,例如 `pre-commit`、`fix-login`:

| 表面 | 值 |
| --- | --- |
| workspace label | `--label pre-commit` |
| branch | 按仓库的命名约定,例如 `chore/pre-commit`;仓库没约定就用短名 |
| agent 名 | `pre-commit` |

任务来自 issue / ticket 时,按仓库约定把编号带进分支名即可,流程不变。agent 名必须匹配 `[a-z][a-z0-9_-]{0,31}` 且在 session 内唯一。这样 `herdr agent prompt pre-commit "..."` 不用查 pane id,侧边栏一眼就能对上。

## 硬性要求

- **永远带 `--no-focus`** —— 不能抢用户的焦点,一次都不行。
- **开了 worktree 的,所有改动只发生在它自己的 worktree 里。** 不要在主 checkout 或别人的 worktree 里动手。
- **不要猜 id。** 并行创建时 id 不保证有序(实测 `w6, w8, w7, w9`),一律从 JSON 解析。
- **`--trust-repository` 只在用户确认过该仓库后才用**,它不是失败重试开关。
- **信息不全就停下来问**:任务说不清、repo root 不确定、用哪个 agent kind 不知道。

## 读 worker 的输出

- 状态汇总:`herdr agent list`。
- 读屏幕必须用 `--source visible`。pi 等 TUI 走 alternate screen,`recent-unwrapped` 读回来是空白。
- **不要把状态当完成信号。** Antigravity、Grok 一回到提示符就算 `idle`,后台任务可能还在跑;`agent wait` 观察的是 agent 状态,不是任务完成。

## 回报:让 worker 写文件,别抓屏幕

每个 worker 结束时写 `<它的 checkout>/.herdr-report.md`:做了什么、改了哪些文件、怎么验证、还剩什么。

主 agent 汇总这些文件回报给用户 —— 不要去翻 N 个 pane 的屏幕。

## 收尾

- **不要自己删 worktree。** PR 合并后由用户发起,或经用户明确确认。
- `herdr worktree remove --workspace <id>` 删 checkout、**保留分支**;`herdr workspace close` 只关 Herdr 状态、不碰 git。两条路别混。
- 关闭带子 worktree 的主 workspace 要带 `--group`,否则返回 `workspace_group_close_required`。

## 边界

Herdr 只负责**拓扑**:checkout、pane、agent 的位置。分支、commit、PR、合并后删分支,都是 git 的事。不要用 Herdr 的命令去动 git 历史。

## 主会话的位置

并行派活时,主会话是调度台:建拓扑、派工、汇总。它自己也要写代码时,就算一个写代码的 agent,按上面「什么时候开 worktree」的规则计数。

## 反模式速查

| 反模式 | 为什么错 |
| --- | --- |
| 建了 worktree 却不挂进 Herdr,或 `cd` 进去干活 | 侧边栏看不见,而且 cwd 改不掉 |
| 只有一个 agent 在写也开 worktree | 多一层拓扑,没换来任何隔离 |
| 多个 agent 同时写同一个 checkout | 互相覆盖,测试结果不可信,diff 分不清是谁的 |
| 主会话里用内部 subagent 干要并行写代码的活 | 没有 pane,就没有屏幕可跳、没有 `blocked` 可看 |
| `herdr pane move` 搬自己的 pane | 不带 cwd,搬完标签是新的、分支还是旧的,布局开始说谎 |
| 一件事拆给两个 agent | 并行粒度错了,合并成本远大于收益 |
