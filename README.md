# pstack-herdr

[poteto/pstack](https://github.com/poteto/plugins/tree/main/pstack) 的个人改编版,适配在 Herdr 里跑多家模型(Claude / Codex / Antigravity)的环境。

上游本地副本:`~/Developer/poteto-plugins/pstack`。原作 MIT 许可,见 [LICENSE](LICENSE)。

## 内容

| skill | 调用方式 | 相对上游的改动 |
| --- | --- | --- |
| `arena` | `/arena` 手动 | 重写:只做方案;多家模型经 Herdr 起在 2×2 tab 里;匿名评审 |
| `figure-it-out` | `/figure-it-out` 手动 | 去掉对 poteto-mode / architect 的依赖 |
| `show-me-your-work` | `/show-me-your-work` 手动 | 交叉审查改用 Herdr 起别家模型;不读 Cursor 的 transcript 目录 |
| `principle-*`(20 条) | 自动可见 | 去掉 `disable-model-invocation`,description 常驻作为原则索引 |

## 安装

每个 skill 目录软链接到 `~/.agents/skills/` 和 `~/.claude/skills/`。
