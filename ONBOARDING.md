# Onboarding: from no GitHub account to your first merged change

Written for Tanner; works for anyone joining the CORELink repo.

## 1. GitHub account (5 minutes)

1. Go to https://github.com/signup and create an account. Use the username you want to be known by in commits.
2. Turn on two-factor authentication when prompted (GitHub requires it for contributors).
3. Send your username to Jacob. He will invite you to the `core-wow-community` organization. Accept the
   invitation from the email or from https://github.com/notifications.

## 2. Tools (10 minutes)

**Mac**
```
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"   # if you don't have Homebrew
brew install git gh lua
```

**Windows** (PowerShell)
```
winget install Git.Git GitHub.cli DEVCOM.Lua
```
Then open a new "Git Bash" window for everything below.

Log in once:
```
gh auth login --web --git-protocol https
```

## 3. Get the code (2 minutes)

```
git clone https://github.com/core-wow-community/CORELink.git
cd CORELink
tests/run.sh                 # should end with "0 failed"
```

## 4. Point your game at the repo

```
scripts/install-local.sh     # Mac default path; on Windows pass your flavor folder, e.g.
scripts/install-local.sh "/c/Program Files (x86)/World of Warcraft/_classic_beta_"
```
This links the repo's `CORELink/` folder into `Interface/AddOns`. Your old copy is moved aside as a backup.
From now on, save a file, type `/reload` in game, and the change is live.

## 5. Making a change

```
git switch main && git pull                      # start from the latest
git switch -c feat/my-change                     # feat/ fix/ docs/ chore/
# ...edit CORELink/CORELink.lua, /reload, test with two characters in two guilds...
tests/run.sh                                     # add a check in tests/harness.lua for new behaviour
git add -A && git commit -m "Add my change"
git push -u origin feat/my-change
gh pr create --fill                              # then fill in the PR template on GitHub
```

`main` is protected: nobody can push to it directly, and a pull request cannot be merged until CI passes
(the tests, and a check that the addon's interface number matches the live game client). No reviewer approval
is required, but fill in the PR template honestly: what it does for players, commands, protocol impact, how
you tested. Press the merge button when the checks are green (it creates a merge commit; history is kept).

## 6. Vibe coding with an AI agent

Open the `CORELink` folder in Claude Code, Cursor, or Codex. The agent reads `AGENTS.md` automatically and
gets the branching rules, the test command, the WoW API gotchas, and the review checklist. Useful prompts:

- "Use /start-feature to begin work on <idea>" - creates the branch correctly.
- "Review PR 7 with /review-pr" - gameplay-impact review before merging.
- "Run /test-addon" - syntax check and harness.

If the agent proposes relaying chat from a timer or event handler, or sending addon messages to General,
point it at `agents/wow-api-gotchas.md`. Those are the two mistakes that cost us a week.

## Where things are

| Need | Look at |
|---|---|
| How the addon works, all `/cl` commands | `README.md` |
| Branch and release rules | `CONTRIBUTING.md` |
| What the game lets addons do | `agents/wow-api-gotchas.md` |
| How to turn an idea into a PR | `agents/feature-requests.md` |
| What gets a PR sent back | `agents/review-checklist.md`, `.github/pull_request_template.md` |
