# greptile skills

skills and scripts for reviewing code with the greptile cli.

install and sign in to the cli first:

```sh
bun add --global greptile
greptile login
```

## skills

- `review-changes` reviews committed changes on your local branch.
- `address-pr-feedback` finds and helps resolve pull request, merge request, and perforce feedback.
- `greploop` reviews, fixes findings, and repeats until the review is clean.
- `greptile-cli` explains the cli commands, output, and common workflows.

install all skills with:

```sh
bunx skills add greptile-projects/skills
```

## scripts

add greptile instructions to a repository:

```sh
sh scripts/add-greptile-context.sh /path/to/repository
```

install the optional pre-push review hook:

```sh
sh hooks/install.sh --repo /path/to/repository
```

the hook requires a successful greptile review before pushing. a review below the required confidence asks for confirmation in an interactive terminal and blocks the push everywhere else.

bypass it once with `git push --no-verify` or `GREPTILE_SKIP_REVIEW=1 git push`.

reviews time out after 25 minutes by default. set `GREPTILE_REVIEW_TIMEOUT_SECONDS` to a positive number of seconds to change the limit.

run the hook tests with:

```sh
sh hooks/test-pre-push.sh
```
