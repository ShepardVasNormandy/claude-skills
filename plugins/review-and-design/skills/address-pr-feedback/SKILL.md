---
name: address-pr-feedback
description: Helps a PR author work through the open review comments on their pull request. Fetches unresolved review threads from GitHub, groups them by file and theme, proposes a code fix or a reply for each one, applies fixes only after the user agrees, and drafts replies for the user to post. Use when the user asks to address, handle, triage or answer review comments or PR feedback on their own PR.
allowed-tools: Bash(bash ${CLAUDE_SKILL_DIR}/scripts/list-open-threads.sh*), Read, Grep, Glob, Edit
---

# Address PR feedback

Help the author close every open review thread on their PR, with a fix or a reply, without touching code they have not agreed to change.

Requires: `gh` (authenticated) and `jq`. If either is missing or `gh auth status` fails, tell the user what to install or run (`gh auth login`), then stop.

## Step 1: Fetch the open threads

Run:

```bash
bash ${CLAUDE_SKILL_DIR}/scripts/list-open-threads.sh <pr>
```

`<pr>` is a PR number or URL. Leave it out to use the PR of the current branch. Add `-R owner/repo` when working outside the repository. The script prints a JSON array of unresolved threads with `id`, `path`, `line`, `author`, `body`, `isOutdated`, `url` and the full `comments` list.

If the array is empty, tell the user there is nothing open and stop.

Make sure the local branch is the PR's head branch and is up to date before you propose fixes. If it is not, tell the user and ask how to proceed.

## Step 2: Group the threads

Group the threads first by file, then by theme inside the file. Themes are things like naming, error handling, tests, performance, API shape, or a question that needs an answer. When the same remark appears in several files (for example "use the money type for refund amounts"), make it one cross-file group.

Read the code at each `path` and `line` before you classify the thread. For a thread with `isOutdated: true` or `line: null`, check whether the current code still has the problem. If it is already fixed, say so and propose a short reply that points to the change.

Show the user an overview:

```
src/orders/refunds.ts (3 threads)
  Validation: 2 threads, alice
  Naming: 1 thread, bob
src/inventory/stock.ts (1 thread, outdated)
Cross-file: "amounts as integer cents" (4 threads)
```

## Step 3: Propose a fix or a reply

Work through one group at a time. For each thread give:

- the reviewer's point in one sentence, with a link to the thread;
- your assessment: agree, partly agree, or disagree, with the reason from the code;
- the proposal: a code change (show the diff), a reply, or both.

Propose a reply instead of a change when the comment is a question, when the change is out of scope for the PR, or when the code is right as it is. Explain why in the reply, with a reference to code or docs. When a fix belongs in a follow-up, say so and offer to draft the follow-up ticket text.

When you are unsure what the reviewer means, say so and draft a clarifying question instead of guessing.

## Step 4: Apply fixes after agreement

Apply a change only after the user says yes to that change or to the whole group. Then:

1. Make the edit.
2. Run the checks that cover the changed code (the relevant tests, type check, lint) and report the result as it is.
3. Note which thread the change addresses.

Do not commit, push, post comments or resolve threads unless the user asks you to. Leave that to the author.

## Step 5: Draft the replies

At the end, give the user one reply per thread, ready to paste, grouped in the same order as the overview. Each reply:

- starts with what was done ("Changed to integer cents in `refunds.ts` and `ledger.ts`.") or the answer to the question;
- is short and specific, and refers to code by file name;
- stays polite and direct, and matches the tone of the thread.

Mark which threads are fixed in the working tree, which only need a reply, and which wait on a decision by the user.
