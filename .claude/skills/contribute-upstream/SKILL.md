---
name: contribute-upstream
description: Ground yourself in current upstream NemoClaw/OpenShell contribution practice before touching upstream code. Use proactively when the user mentions contributing back, opening an upstream PR, fixing a bug in upstream, filing an issue against NVIDIA/NemoClaw or NVIDIA/OpenShell, or any work that will land as a PR against either repo. Scans the upstream repo for live practice docs and skills (not hardcoded paths) so it stays valid as upstream evolves.
allowed-tools: Bash Read Grep Glob WebFetch
---

# Contribute upstream

You're about to do work that will land in NVIDIA/NemoClaw or NVIDIA/OpenShell. The cookbook is not the source of truth for upstream practice — the upstream repo is, and it evolves. This skill grounds you in *current* upstream practice via live scan, then applies the design discipline the cookbook has learned through PRs that got reverted.

## Phase 1 — Locate and refresh the upstream clone

```bash
for repo in ~/NemoClaw ~/OpenShell; do
  [ -d "$repo/.git" ] && (cd "$repo" \
    && git fetch origin --tags --quiet \
    && echo "$repo @ $(git log --oneline -1)")
done
```

If no clone exists for the repo you're changing, stop and ask the user to clone it. Working from a stale or absent checkout is the most reliable way to ship a change against assumptions that no longer hold.

## Phase 2 — Scan for current upstream practice

Don't assume the file or skill names. Discover what exists *now*:

```bash
UPSTREAM=~/NemoClaw   # or ~/OpenShell, depending on target

# Contributor-relevant skills — whatever the repo currently has
find "$UPSTREAM/.claude/skills" "$UPSTREAM/.agents/skills" \
  -maxdepth 2 -name SKILL.md -path '*contributor*' 2>/dev/null

# Repo-root practice docs (load whichever exist)
ls "$UPSTREAM"/CLAUDE.md "$UPSTREAM"/AGENTS.md "$UPSTREAM"/CONTRIBUTING.md 2>/dev/null

# Ratchets / budget checks that may apply to your change
ls "$UPSTREAM"/scripts/checks/ 2>/dev/null

# Canonical lint / test / build commands
[ -f "$UPSTREAM/Makefile" ] && grep -E '^[a-z][a-z-]*:' "$UPSTREAM/Makefile" | head
python3 -c "import json; d=json.load(open('$UPSTREAM/package.json')); print('\n'.join(sorted(d.get('scripts',{}))))" 2>/dev/null

# Hook config (canonical pre-commit / pre-push pipeline)
ls "$UPSTREAM"/.pre-commit-config.yaml "$UPSTREAM"/.github/workflows/ 2>/dev/null
```

Read every file the scan surfaces. If an upstream skill covers PR creation, doc updates, or any other mechanic — invoke it. **Do not reinvent the PR template, the verification checklist, the sign-off rules, or the gate commands.** Upstream owns those.

If something you expect is missing (a skill renamed, a doc reorganized), note it but don't fail — upstream may have restructured. Work with what's actually there.

## Phase 3 — Search for related in-flight work

```bash
gh search issues --repo NVIDIA/NemoClaw "<short bug or feature description>" \
  --include-prs --limit 20 --json title,state,url,createdAt
```

If something close to your intent is open, attach to it rather than duplicating. If reverts or supersession PRs exist around the same code surface, read them — they tell you what *almost* shipped and why it didn't. That's the cheapest lesson you'll get all week.

## Phase 4 — Apply design discipline

Six rules. Walk through every one before writing code. If you can't satisfy one, you don't yet understand the change well enough to ship it.

**1. Root cause first.** Articulate the root cause in one or two sentences. If you can only describe the symptom, keep investigating. The symptom is "users see error X." The root cause is the chain of conditions that produce X. Patching the symptom without understanding the chain is how reverts happen.

**2. Mirror reality.** When your change adds a probe / check / diagnostic that exercises a real system, locate the canonical setup for that real system in the codebase and copy its configuration exactly. Same docker network mode, same `--add-host` flags, same env, same entrypoint shape. Approximations leak across host/driver/network configurations and produce false positives that block real users.

**3. Diagnostic = proven fact.** Error messages state what your code can prove. Hypotheses about cause (firewall, DNS, routing) go as one of several possible causes, never as the headline of an actionable error. Wrong diagnoses waste user time and erode trust.

**4. Conservative defaults for new diagnostics.** First iteration of a check warns and continues. Fail-hard only when you have proof of a known-bad state, not when you fail to reach a known-good one. The cost of being wrong about a diagnosis is asymmetric — a misleading warning is recoverable; a misleading block sends users in circles.

**5. Validate against the deployment matrix.** Identify which drivers / hosts / configurations the path you're changing supports (check existing code for env switches like `OPENSHELL_DRIVERS`, platform forks, conditional imports). Validate against at least two distinct configurations, or scope the PR to one and call that out explicitly in the PR body.

**6. Live-reproduce first.** If the bug has a reproduction, run the proposed fix mechanism manually against it *before* writing code. The reproduction is the cheapest test you'll ever have. Code is the last thing you write, not the first.

## Phase 5 — Hand off to upstream PR creation

When the change is built, tested, and validated against the matrix, invoke whichever upstream skill the Phase 2 scan surfaced for opening contributor PRs. Follow it exactly. Don't reinvent the PR template, the verification checklist, the sign-off requirements, or the `gh pr create` flags. Upstream evolves these on its own cadence; the skill in upstream's repo is authoritative.

If your change affects user-facing behavior (new diagnostics, changed defaults, new commands, modified messages), Phase 2 should have surfaced a docs-update skill — invoke that too, in the same PR. Doc-update is not optional for user-facing changes; upstream explicitly enforces this.

### After the PR is open — run the upstream nightly E2E suite

For any substantive change, the upstream nightly E2E suite is the highest-signal validation available before human review. Trigger phrase: **"run the nightly E2E for my PR and provide me a link."** Discover the dispatch surface dynamically (workflow file lives under `.github/workflows/`, typically named `nightly-e2e.yaml`; inputs may include a `jobs` filter for running a subset):

```bash
gh workflow list --repo NVIDIA/NemoClaw | grep -i nightly
gh workflow view nightly-e2e.yaml --repo NVIDIA/NemoClaw    # inputs + job names
gh workflow run  nightly-e2e.yaml --repo NVIDIA/NemoClaw --ref <pr-branch> [-f jobs="<comma-separated>"]
gh run list      --workflow nightly-e2e.yaml --repo NVIDIA/NemoClaw --branch <pr-branch> --limit 1 --json url,databaseId
```

Post the run URL in the PR conversation so reviewers have one place to land. The exact workflow name, the input shape, and the dispatch permissions may change — re-discover via Phase 2's scan rather than memorizing.

## After merge — merged ≠ done

A merged PR isn't done until it survives ~48 hours without a revert, supersession, or follow-up issue. Watch the surface area:

```bash
# Did the merge get reverted or has a fix-on-top landed in the same area?
gh search issues --repo NVIDIA/NemoClaw "<your PR title keywords>" \
  --include-prs --limit 10 --json title,state,url,createdAt
git -C ~/NemoClaw log --oneline <your-merge-sha>..origin/main -- <files-you-changed>
```

If a revert or follow-up appears, treat it as data. Identify which of the six rules above wasn't satisfied. Internalize. The next change of similar shape should not make the same mistake. Don't keep a journal — the lesson lives in the engineer, not a document.

## Common mistakes to avoid

- **Loading no upstream skills.** If Phase 2 finds skills relevant to your task and you don't load them, you'll freelance practice that upstream already specified. That's how PR templates, sign-offs, and gates drift.
- **Hardcoding upstream file names in your own notes or follow-ups.** Upstream restructures. Always re-scan.
- **Declaring victory at merge.** See "merged ≠ done." A merge is a checkpoint, not the finish line.
- **Skipping Phase 4 rule #1.** Of the six rules, root-cause is the one most often skipped and most often the source of reverts. If you can't write the root cause in one sentence, the fix is premature.
