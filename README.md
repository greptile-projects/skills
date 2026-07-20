# Greptile agent extensions

Official Greptile plugins and agent skills for reviewing local changes, addressing pull-request feedback, and iterating until Greptile gives a change a 5/5 review.

The repository keeps one canonical copy of every skill under `plugins/greptile/skills/` and distributes that same content through Codex, Claude Code, and the open agent skills ecosystem.

## Available skills

| Skill | Purpose |
| --- | --- |
| `review-changes` | Review local changes with Greptile before opening a pull request. |
| `address-pr-feedback` | Inspect and address unresolved PR feedback, failing checks, and incomplete change descriptions. |
| `greploop` | Repeatedly fix and re-review a change until it reaches 5/5 with no unresolved comments. |

## Install with skills.sh

List the available skills:

```bash
npx skills add greptileai/skills --list
```

Install all Greptile skills for your preferred agent:

```bash
npx skills add greptileai/skills
```

Or install selected skills non-interactively:

```bash
npx skills add greptileai/skills \
  --skill review-changes \
  --skill address-pr-feedback \
  --skill greploop
```

## Install as a Claude Code plugin

```bash
claude plugin marketplace add greptileai/skills
claude plugin install greptile@greptile
```

The skills are available under the `greptile` plugin namespace.

## Install as a Codex plugin

```bash
codex plugin marketplace add greptileai/skills
codex plugin add greptile@greptile
```

The Codex plugin includes Greptile branding and starter prompts in addition to the shared skills.

## Repository layout

```text
.
├── .agents/plugins/marketplace.json       # Codex marketplace
├── .claude-plugin/marketplace.json        # Claude Code marketplace
└── plugins/greptile/
    ├── .codex-plugin/plugin.json           # Codex manifest
    ├── .claude-plugin/plugin.json          # Claude Code manifest
    ├── assets/                             # Plugin branding
    └── skills/                             # Shared Agent Skills
```

To add another plugin, create `plugins/<plugin-name>/`, give it the appropriate client manifests, and register it in both marketplace files. Keep reusable workflows inside the plugin's `skills/` directory so skills.sh and plugin clients consume the same source files.

## Local validation

```bash
claude plugin validate .
npx skills add . --list
```

Codex validation is run with the `plugin-creator` validator before publishing changes.
