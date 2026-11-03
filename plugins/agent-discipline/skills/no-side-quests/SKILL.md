---
name: no-side-quests
description: Holds a task to its stated scope. The agent finishes the requested change in full and leaves everything else alone, and lists unrelated problems it spots (a broken test elsewhere, an old dependency, code it would restructure) at the end of its reply for the user to decide on. Trigger on /no-side-quests or when the user says "keep it narrow", "only touch what I mentioned", "don't fix other things", "leave the rest", "scope creep" or "you changed too much". Also worth loading before a small, targeted change in a codebase where unrelated issues are likely to come up.
---

# No side quests

When the user asks for X, do X. Do it completely, and stop there.

## The rule

1. Work out the scope from the request: which files, which behaviour, which command. If the request is vague enough that two readings lead to different changes, ask before you start.
2. Do everything the task needs inside that scope. Finishing the task properly is part of the scope: tests for the change, a type error you caused, an import the change needs.
3. Anything outside the scope that you notice goes into a note. Do not fix it, start investigating it, or change files for it.
4. If the task cannot be finished without going outside the scope, stop and ask. Say what you need to touch and why.

## What counts as a side quest

- A test, lint rule or type check that was already failing before your change.
- An outdated or vulnerable dependency.
- Code you would structure differently, naming you would change, comments you would remove.
- A bug in a nearby function that the task does not depend on.
- Formatting changes in lines you did not otherwise edit.
- Extra features, options or docs the user did not mention.

If you are unsure whether something is in scope, treat it as a side quest and put it in the note.

## The note

End your reply with a short list, only when there is something to report:

```
Also noticed, left as is:
- <what> in <where>: <one line on why it matters>. <the next step, if obvious>.
```

Keep each item to one line. Do not argue for fixing it. The user decides.

## Examples

**Renaming a CSS class while an unrelated test fails.** The user asks to rename `.btn-primary` to `.button-primary`. You rename it in the stylesheet and in the four components that use it, then run the tests. `cart-total.test.ts` fails on a rounding assertion, and it failed the same way before your change. You leave it alone.

```
Also noticed, left as is:
- cart-total.test.ts fails on a rounding assertion, also on main before this change.
```

**Updating a README while noticing an outdated dependency.** The user asks to fix the install steps in the README. While checking the commands, you see that `package.json` pins a version of `vite` two majors behind. You fix the README and nothing else.

```
Also noticed, left as is:
- package.json pins vite 4. The current major is 6, so an upgrade would need its own change.
```

**Fixing a bug next to a function you would refactor.** The user asks to fix the off-by-one in `paginate()`. The function next to it, `buildQuery()`, repeats the same filter logic three times. You fix `paginate()`, add a test for the edge case, and leave `buildQuery()` as it is.

```
Also noticed, left as is:
- buildQuery() in src/orders/query.ts repeats the status filter three times. It could share one helper.
```

**A task that cannot be finished inside the scope.** The user asks to add a `notes` field to the order form. The API rejects unknown fields, so the form cannot save it without a backend change. You stop and ask: "Saving the note needs the API to accept a `notes` field in `POST /orders`. Should I change the API as well, or only the form for now?"

## When the user pushes back

If the user says the last turn did too much, ask which of the extra changes to keep. Revert the others, and from then on follow the rule above for the rest of the conversation.
