---
name: arena
description: "让不同家族的模型(Claude / OpenAI / Google)在 Herdr 里各自独立出一份方案,由当前会话主持:交叉评审、挑底稿、嫁接其他方案的长处,交给用户拍板。只用于方案类问题:架构、设计、技术选型。用于 /arena、'arena this'、'丢进 arena'。不写代码。要求 HERDR_ENV=1。"
disable-model-invocation: true
---

# Arena(Herdr 方案版)

改编自 poteto/pstack 的 [`arena`](https://github.com/poteto/plugins/blob/main/pstack/skills/arena/SKILL.md)。

沿用原版的思想:同一个问题让多个模型**独立**作答,只给评审看的 rubric,换一家模型交叉评审,主持人逐份读完、按 rubric 挑底稿、亲手嫁接,记下放弃了什么。

和原版的不同:

- **只做方案,不写代码。** 适用于架构、设计、选型这类「定了就难改」的决定。方案定下来之后直接实现,不再横向比较实现。
- **不开 worktree。** 参赛者都在当前 checkout 里只读代码,只往 `/tmp/arena-<slug>/` 写自己的方案文件。
- **多家模型靠 Herdr。** 每个模型家族是一个独立的 CLI agent,不是当前工具的内部 subagent。
- **最后由用户拍板。** 主持人给出综合方案和推荐,不替用户做最终决定。

## 什么时候不该用

- 问题是机械性的,或者方案形状已经明确 —— 直接做。
- 已经定下来的设计 —— 再跑一轮是过度设计。
- 需要比较可运行的实现 —— 不在本 skill 范围内。

## 前提

```bash
test "${HERDR_ENV:-}" = 1
```

不满足就停下,说「我不在 Herdr 的 pane 里,arena 需要它」。不要退化成当前工具的内部 subagent —— 那样只剩一家模型,arena 失去意义。

## 角色与模型

主持人就是**调用 arena 的当前会话**(Claude Code、Codex、agy 都可以),不参赛。三家参赛者照常全部派出,包括和主持人同家族的那一个。

| 角色 | Herdr kind | 启动参数(`agent start ... --` 之后) |
| --- | --- | --- |
| 参赛者 `claude` | `claude` | `--effort high`(模型用 settings 默认:Opus 5.5) |
| 参赛者 `gpt` | `codex` | `-m gpt-6.1-sol -c model_reasoning_effort="high"` |
| 参赛者 `gemini` | `agy` | `--model gemini-4-carbon-medium` |
| 交叉评审 `judge` | `agy` | `--model gemini-4-argon-high` |

**启动参数只指定模型和推理强度,不传任何权限、沙盒、审批相关参数**(`--permission-mode`、`-s`、`-a`、`--mode` 等)。用户的各 CLI 默认已是最高权限;额外传参只会把它们收紧,导致参赛者卡在审批上找用户要权限。「只读」靠 prompt 约束,再由 Phase F 的 `git status` 基线对比兜底。

改模型只改这张表。规则:

- **评审必须和主持人不同家族。** 默认评审用 `agy`;主持人自己是 agy 时,评审改用 `codex`(选一个不在参赛者里的 GPT 模型)。
- **评审不能和任何参赛者是同一个模型**,否则它在给自己打分。
- 评审是纯判断活,模型和推理强度往高开;参赛者可以按需降档。

## 开局

先开一个 todolist,一个阶段一项:

1. Frame
2. Fan out
3. Cross-judge
4. Pick
5. Graft
6. Check
7. Hand off

## Phase A:定题(Frame)

所有参赛者拿到同一份题目,题目就是契约。

1. **把问题写成一个决定。** 「X 该怎么设计」「A 和 B 选哪个」,附上已知约束(性能、平台、兼容性、团队习惯)和明确不考虑的范围。
2. **列出共享背景。** 参赛者应该读的文件、文档、spec 路径。
3. **定 rubric。** 先说清「好的方案长什么样」,再拆成 3–6 条可逐条打分的具体标准。具体:`冷启动时不阻塞主线程`;含糊:`性能好`。rubric 只给主持人和评审,**不给参赛者**。
4. **定 slug。** 短、小写,如 `asrcache`。agent 名为 `a-<slug>-<runner>`,须匹配 `[a-z][a-z0-9_-]{0,31}`。
5. **记录基线。** `git status --porcelain > /tmp/arena-<slug>/baseline.txt`,用于事后确认没人改过仓库。

写入:

```text
/tmp/arena-<slug>/
  brief.md        # 题目 + 约束 + 共享背景(参赛者看)
  rubric.md       # 只给评审和主持人
  baseline.txt
  proposals/      # 参赛者各写一份,带模型名
  mapping.txt     # 匿名标签 ↔ 参赛者,只有主持人看
  synthesis.md    # Phase G 的综合记录
/tmp/arena-<slug>-judge/   # 评审的工作目录,只放评审该看的东西
  brief.md  rubric.md  A.md  B.md  C.md  judge.md
```

题目含糊时先问用户,不要带着含糊开跑 —— 三份方案会各自往不同方向猜。

## Phase B:并行出题(Fan out)

建一个专用 tab,不挤用户当前的 pane。布局是 2×2 网格,参赛者占三格,右下角留给评审:

```text
┌──────────┬──────────┐
│ claude   │ gpt      │
├──────────┼──────────┤
│ gemini   │ (judge)  │
└──────────┴──────────┘
```

```bash
herdr tab create --workspace "$HERDR_WORKSPACE_ID" --cwd <repo-root> \
    --label arena-<slug> --no-focus
#   → 解析 .result.root_pane.pane_id,作为 claude 格
herdr pane split <claude_pane> --direction right --cwd <repo-root> --no-focus   # → gpt 格
herdr pane split <claude_pane> --direction down  --cwd <repo-root> --no-focus   # → gemini 格
#   → 每次解析 .result.pane.pane_id

herdr agent start a-<slug>-<runner> --kind <kind> --pane <pane_id> -- <args...>
herdr agent prompt a-<slug>-<runner> "<参赛者 prompt>"     # 不带 --wait,三个同时跑
herdr agent get a-<slug>-<runner>                           # 几秒后确认状态是 working
```

- 不要猜 id,一律从 JSON 解析。永远 `--no-focus`。
- **确认 prompt 真的被接住。** `agent_prompted` 只说明字写进了终端,不代表 agent 开始干活。agy 等 CLI 启动时可能弹公告(如「Introducing Gemini …  esc to dismiss」)把 prompt 吞掉。发完几秒后状态仍是 `idle`:`agent read --source visible` 看屏幕,输入框为空就 `agent send-keys <name> esc` 关掉弹窗再重发;输入框里还有字就只补一个 Enter,不要重发。
- cwd 是仓库根目录,这样参赛者能读代码;写入只发生在 `/tmp/arena-<slug>/`。

参赛者 prompt(三人相同,只有文件名不同)。被其他 skill 调用、且调用方给了自己的参赛者 prompt 或方案模板(如 architect 的 `references/runner-prompt.md`)时,用调用方的,只保留下面的输出路径:

```text
请为这个设计问题给出一份方案:/tmp/arena-<slug>/brief.md

把方案写到 /tmp/arena-<slug>/proposals/<runner>.md,包含:
1. 你对问题的理解和你做的假设
2. 推荐方案:形状、关键接口/数据结构、为什么
3. 考虑过的替代方案,以及为什么没选
4. 依据:代码引用用 path:line 标出;对外部库/平台能力的断言注明来源,没核实的标「未核实」
5. 风险,以及什么新信息会让你改变推荐
6. 你最不确定的一点
```

### 写 prompt 的原则

- **只说做什么。** 交付物定得足够具体(一个确定路径的文件),agent 自然只做这件事。不列「不要改仓库」「不要 commit」之类的禁令 —— 它们是噪音,还会把被禁止的事放进注意力里。万一越界,由 Phase F 的基线对比兜底。
- **任务的「为什么」写进 brief。** 约束背后的原因(例如「首字延迟优先,因为冷加载会明显拖慢听写」)帮参赛者在 brief 没写到的地方做对取舍。
- **arena 机制的「为什么」不说。** 不提有别的模型在做同一题、不提评审和打分。这些元信息会改变参赛者的行为。
- **匿名由主持人负责。** 不要求参赛者隐藏身份;主持人在 Phase C 做匿名副本时去掉能暴露模型的内容。

### 等待完成

```bash
herdr agent wait a-<slug>-<runner> --timeout 1200000
test -s /tmp/arena-<slug>/proposals/<runner>.md
herdr agent get a-<slug>-<runner>      # 状态不是 working
```

- **完成 = 方案文件存在且非空,并且 agent 已不在 working。** 两个条件缺一不可:agent 状态单独不可靠(agy 回到提示符就算 `idle`);文件单独也不够(参赛者可能先写文件,再继续自检或补写)。
- 在后台循环等三份都满足条件,不要逐个前台阻塞。
- `blocked`:用 `herdr agent read <name> --source visible` 看是什么。**不替用户点批准**,转述给用户决定。
- 某个参赛者交不出:按 N-1 继续,在综合记录里写明掉队者和原因。

## Phase C:交叉评审(Cross-judge)

**所有参赛者交稿后**才起评审。

1. **建评审专用目录** `/tmp/arena-<slug>-judge/`,只放 `brief.md`、`rubric.md` 和匿名副本。不要让评审在 `/tmp/arena-<slug>/` 里工作 —— 那里的 `proposals/<runner>.md` 带着模型名,评审一 `ls` 匿名就失效。
2. 把方案复制成匿名副本:`proposals/<runner>.md` → `A.md`、`B.md`、`C.md`,顺序打乱,并去掉能暴露模型或公司的字样(自称、署名、工具名)。对应关系写进 `/tmp/arena-<slug>/mapping.txt`。
3. 在 arena tab 的右下格起评审(从 gpt 格往下切,补齐 2×2),同样确认它真的进入 working:

```bash
herdr pane split <gpt_pane> --direction down --cwd /tmp/arena-<slug>-judge --no-focus
herdr agent start a-<slug>-judge --kind agy --pane <pane_id> -- <评审参数>
herdr agent prompt a-<slug>-judge "<评审 prompt>"
```

评审 prompt:

```text
请评审同一个设计问题的几份方案,把评审写到 /tmp/arena-<slug>-judge/judge.md。

题目:/tmp/arena-<slug>-judge/brief.md
评分标准:/tmp/arena-<slug>-judge/rubric.md
方案:/tmp/arena-<slug>-judge/ 下的 A.md、B.md、C.md
仓库(用于核实方案中的代码引用):<repo-root>

judge.md 包含:
1. 每份方案逐条评分(1–5),每条一句依据
2. 抽查每份方案里支撑结论的关键代码引用和事实断言,标出不成立的
3. 推荐哪一份做底稿及理由,以及其他方案里值得移植的点
```

评审跑的同时,主持人开始 Phase D。

## Phase D:挑底稿(Pick)

**挑之前把每份方案从头读到尾。** 只扫一眼的话,最后胜出的往往只是表面最眼熟的那份 —— 主持人对自己同家族模型的写法天然顺眼,这一点要主动提防。

- 按 rubric **逐条**打分,不凭整体感觉。
- 与 `judge.md` 对照。底稿一致 = 确认;不一致 = 一方有偏见或 rubric 含糊,读双方理由再定,并把分歧写进记录。
- 挑「未来维护者最容易在不破坏不变量的前提下扩展」的那份。打平时选边界更干净、表面积更小的。

## Phase E:嫁接(Graft)

把每份落选方案再过一遍,找出值得移植进底稿的东西。通常每份一两点。

- **主持人亲手重写**,让综合方案在一个统一的思路下自洽。不要拼贴段落。
- 三份殊途同归 = 强共识信号,直接采用共识形状,不用嫁接。
- 三份差别特别大 = Phase A 没定清楚。回去补约束或拆问题,重新跑,不要把几份拼在一起凑个平均。

## Phase F:核实(Check)

方案没法跑测试,但方案里的事实可以核实。arena 不给免检。

1. 综合方案里每一条**承重的**断言 —— 代码里现有的接口和行为、库或平台的能力、版本限制 —— 由主持人亲自核实,读代码或查文档。核实不了的明确标「未核实」。
2. `git status --porcelain` 与 `baseline.txt` 对比,确认没有参赛者或评审改过仓库。若有改动,报告给用户,**不要自行还原**。

核实推翻了某个前提:要么 Phase A 错了(重新定题),要么某份方案注意到了而你漏了嫁接(回 Phase E)。不要糊过去。

## Phase G:交给用户(Hand off)

被其他 skill 调用时(如 architect),是否停下来等用户拍板由调用方决定;综合记录照写。

写 `/tmp/arena-<slug>/synthesis.md`:

- **推荐方案**:综合后的完整方案
- **底稿**:来自哪个参赛者(此时可以揭晓模型),为什么
- **嫁接**:移植了什么,来自谁
- **放弃**:考虑过但没采用的点及理由 —— 这部分信息量最大
- **评审**:`judge.md` 的结论,与主持人的分歧
- **核实**:哪些断言已核实,哪些未核实
- **掉队者**(如有)
- **需要用户拍板的点**:方案之间真正的取舍,主持人不替用户做

向用户汇报时给出推荐方案的要点、需要拍板的点,以及 `synthesis.md` 和各方案文件的路径。

## 收尾

- 参赛者和评审交完稿后可以退出。arena tab 留着,由用户决定何时关闭(`herdr tab close <tab_id>`)。
- `/tmp/arena-<slug>/` 不删。用户要把方案存进仓库(例如 `docs/` 或 spec),等用户明确要求再做。
- 不写实现代码。用户拍板后要实现,那是 arena 之外的下一步。
