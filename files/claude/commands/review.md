---
description: "Review a GitHub PR or GitLab MR. Accepts a PR/MR number or URL."
argument-hint: "[pr-number | mr-number | github-url | gitlab-url]"
allowed-tools: ["Bash"]
---

You are an expert code reviewer. Follow these steps:

## 1. Detect platform from arguments

Arguments: "$ARGUMENTS"

- If the argument contains `gitlab` → use **GitLab** (`glab` CLI)
- If the argument contains `github` → use **GitHub** (`gh` CLI)
- If the argument is a bare number → check `git remote -v` to detect the platform
- If no argument is provided → check `git remote -v` to detect the platform

## 2. Fetch PR/MR details

**GitHub (gh CLI):**
```
gh pr list                    # if no number given
gh pr view <number>           # get PR details
gh pr diff <number>           # get the diff
```

**GitLab (glab CLI):**
```
glab mr list                  # if no number given
glab mr view <number-or-url>  # get MR details
glab mr diff <number-or-url>  # get the diff
```

For GitLab URLs like `https://gitlab.example.com/group/repo/-/merge_requests/42`:
- Extract the MR number from the URL (the last path segment after `merge_requests/`)
- Run `glab mr view <number>` and `glab mr diff <number>` from the repo directory (or pass `--repo` if needed)

## 3. Analyze the changes

Provide a thorough code review that includes:

- **Overview**: What does this PR/MR do?
- **Code quality and style**: Readability, conventions, consistency with the codebase
- **Specific suggestions**: Concrete improvements with file and line references
- **Potential issues or risks**: Bugs, security concerns, performance implications
- **Test coverage**: Are the changes adequately tested?

## 4. Format the review

```markdown
## Overview
<what the PR/MR does>

## Code Quality
<observations>

## Issues & Risks
- **[severity]** `file:line` — description

## Suggestions
- `file:line` — suggestion

## Test Coverage
<assessment>
```

Keep the review concise but thorough. Focus on correctness, security, and project conventions.
