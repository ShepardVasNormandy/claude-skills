---
name: model-router
description: Splits a request into independent tasks, picks the right model and effort for the orchestrator and for each task, and launches one sub-agent per task in parallel while you stay the orchestrator. Once invoked, it stays active for the rest of the thread and applies to every later request that can be split or parallelized. Use it when a request has several parts, or when the model choice for a sub-agent matters for cost or quality. Works in Claude Code and Codex. Uses Jev for routing when `TYPESAFE_API_KEY` is set; otherwise routes by its own rules.
---

# model-router

You are the orchestrator. Your goal has two parts:

- **Split** the request into tasks, each with its own model and effort.
- **Size** the request as a whole: its global complexity tells which model and effort the orchestrator needs.

Then launch the matching sub-agents in parallel. Do not do the delegated work yourself.

Setup: Node 18+. Optional: `export TYPESAFE_API_KEY=<your Jev key>` to route with Jev. Without a key, you route each task yourself (see Route without Jev). That is a normal mode, not an error.

## Scope: the whole thread

Once invoked, this skill stays active until the end of the thread, or until the user says to stop. It is a working mode, not a one-shot command. Work like a tech lead with a team: you plan, delegate, check and decide. The sub-agents do the work.

For each new user message, and each time new work appears during a task, apply the Steps again when one of these is true:

- The work splits into two or more independent tasks.
- Two or more searches, reads or tool calls can run in parallel.
- One task needs a different model than yours: cheaper for a search or a list, stronger for a hard root cause.

Do the work yourself only when it is one short step (one command, one file read, one answer from what you already know), or when it needs the full conversation context to be done right. Give each delegated task the context it needs: a sub-agent does not see the thread. When the work is small enough to do yourself, do not split it by type only to delegate it. The split by type applies to the tasks you delegate.

## Steps

1. **Split.** Break the request into independent tasks. Write each as one or two sentences: what to do, where, what done looks like. A vague task gets a vague answer. Keep dependent steps in order. If the work is one short step, do it yourself and skip the rest (see Scope).

   One task does one type of work. Each type is an agent in `agents/`: the front matter `description` says what it does, the body is its contract.

   - **search**: find files, rows, logs, or facts.
   - **analysis**: explain a cause, compare options, read a design.
   - **implementation**: write or change code, config, or text.
   - **review**: check work that another task produced.

   Do not mix two types in one task. The router sizes a task from its text. A task that searches and fixes gets a model that is too expensive for the search or too weak for the fix.

   A decision is not a task. When the work needs a choice (a UX option, a trade-off, an API shape), a sub-agent can list the options and their costs. You or the user choose. When the choice belongs to the user, ask before the next wave starts.

   A review goes to a different sub-agent than the one that wrote the work, in a later wave.
2. **Route.** If `TYPESAFE_API_KEY` is unset, skip the router calls and go to "Route without Jev". Otherwise run the router once for the whole request (the orchestrator) and once per task, all in parallel in the same message:
   ```bash
   node scripts/route.mjs --tool claude-code "Find why the nightly job sends duplicate order confirmations."
   ```
   For the orchestrator call, add `--orchestrator` and give the full request in two or three sentences: the goal, the number of tasks, how they depend on each other.
   ```bash
   node scripts/route.mjs --orchestrator --tool claude-code "<request>"
   ```
   `--orchestrator` caps the tier at `intense`: the orchestrator reads the whole thread, so `frontier` there multiplies the cost. Use `--tool codex` in Codex. Run it from this skill's directory.
3. **Plan.** Write the plan table as text to the user. This is a gate: the table must be visible before the first Agent call. Never put an Agent call in the same message as the router calls. The message after the router results starts with the table, and the Agent calls of wave 1 come after it.

   | Role | Task | Agent | Model | Effort | State |
   |---|---|---|---|---|---|
   | Orchestrator | Find and fix the duplicate order confirmations of the nightly job | - | opus | high | - |
   | Task 1.1 | Find the job that sends the confirmations | search | haiku | - | pending |
   | Task 1.2 | Find the confirmations sent twice last week | search | haiku | - | pending |
   | Task 1.3 | Read the retry config of the email queue | search | haiku | - | pending |
   | Task 2 | Find why a confirmation is sent twice, from the results of 1.x | analysis | opus | high | pending |
   | Task 3 | Make the confirmation send idempotent, from the cause found in 2 | implementation | sonnet | medium | pending |
   | Task 4 | Review the change of 3 against the cause found in 2 | review | opus | medium | pending |

   The number of a task is its wave. Tasks of the same wave (1.1, 1.2, 1.3) run in parallel. Wave 2 starts when wave 1 is done. A wave with a single task has no sub-number (Task 2).

   When a decision sits between two waves, write it as a line between the rows, for example `Decision (user): pick the idempotency key`. It is not a task and gets no model.

   The Agent column is the router's `agent`. If it is not the type you split the task as, the task text mixes two types or says the wrong one: rewrite it and route again. The orchestrator row has no agent.

   The orchestrator row gives the router result for the whole request. Write `-` when `effort` is `null`. You cannot change your own model. If your current model is not the model of the orchestrator row, write a warning under the table that names both models: above your model is a quality risk, below it is a cost. Then continue.

   If a task row is `frontier`, ask the user before you delegate (see Frontier approval).

   The State column tracks each task (see Track the state).
4. **Delegate.** Launch one sub-agent per task, wave by wave. All the tasks of a wave go in the same message. Give each the `model` and `effort` of its row, and the contract of its agent (see Launch the sub-agent).
5. **Orchestrate.** Collect the results, check them, and write the final answer. A wave gets the results of the waves before it.

## Track the state

Each time the state of a task changes, write the full plan table again, with the new State. The user sees which sub-agent runs, on which model and effort, without asking.

| State | When |
|---|---|
| `pending` | The task waits for an earlier wave. |
| `approval` | The task is `frontier` and waits for the user (see Frontier approval). |
| `running` | The sub-agent is launched. |
| `done` | The sub-agent returned and you checked its result. |
| `failed` | The sub-agent returned an error, or a result that does not answer the task. Write the reason in one line under the table. |

Write the table once per message, not once per change. When you launch a wave, the table comes before the Agent calls, with the wave already `running`. When several sub-agents finish in the same turn, one table shows all of them. The orchestrator row keeps `-`.

## Result

```json
{"tier":"basic","model":"haiku","effort":null,"probability":0.75,"runner_up":{"tier":"workhorse","model":"sonnet","probability":0.25},"agent":"search","agent_description":"Find where something is, in code, docs, logs or data. ..."}
```

- `model` and `effort`: what to give the sub-agent. `effort` is `null` when the model has no effort setting.
- `probability`: how sure the router is.
- `runner_up`: present on a close call. If a wrong result costs more than the extra model, take the runner-up. Or make the task text more precise and route again.
- `agent` and `agent_description`: the type of work, from the front matter of `agents/<agent>.md`. Jev picks it in the same call as the tier, from the descriptions.

## Route without Jev

When the script prints `"fallback":true`, size each task yourself with the same rules:

- **Tier:** read the criteria of `tier` in `references/questions.json` and pick the one the task text matches. Judge the task as written.
- **Effort:** pick from the criteria of `effort` in the same file.
- **Model:** map the tier to a model with `references/profiles.json` for your tool. Take the highest effort the model accepts at or below the one you picked, or `-` when its list is empty. For the orchestrator, cap the tier at `intense`.
- **Agent:** the type you split the task as.

Write the source in the Model column, for example `sonnet (fallback)`. The plan table, the waves and Frontier approval work the same way.

## Frontier approval

A `frontier` task does not start without the user's approval. This applies to the router's choice and to a `frontier` runner-up that you want to take.

1. After the plan table, ask the user with the question tool (`AskUserQuestion` in Claude Code, a plain question in Codex). Ask one question per `frontier` task, with two options:
   - **Yes, continue with frontier**: launch the task with the `frontier` model.
   - **Use Opus instead**: launch the task with the `intense` model and the same effort.
2. Write the answer in the Model column: `fable (approved)` or `opus (user)`.
3. The other tasks of the same wave wait for the answer too, so that the wave stays one message.

Do not ask when the user named the model (see Rules).

## Launch the sub-agent

Start the sub-agent prompt with the body of `agents/<agent>.md` (the part after the front matter), then the task. The contract is an instruction, not a permission: a `search` sub-agent still has the edit tools. In Claude Code, use the `general-purpose` sub-agent type.

- **Claude Code:** pass `model` to the Agent tool. It has no effort parameter, so use a sub-agent definition with that effort if one exists. Otherwise write "Reasoning effort: <effort>" in the sub-agent prompt.
- **Codex:** set `model` and `model_reasoning_effort` in the custom agent file, the `[agents]` defaults, or the spawn request.

## Rules

- One task, one type of work, one agent. Decisions stay with you or the user. A review never goes to the author of the work.
- Always show the plan table before you delegate, also when the user names the models or when the router fails. In those cases, write the source in the Model column, for example `sonnet (user)` or `sonnet (fallback)`.
- If the user names a model or an effort, use it. Do not route that task.
- Frontier is rare: a long autonomous task only (from-scratch build or design, deep security audit, deep research). A high-stakes but bounded task is intense plus a review task.
- The task text leaves your machine. Never put secrets, credentials or customer data in it. Summarize instead.
- If the script prints `"fallback":true` (no key, or Jev answered 402 when out of credit), route by yourself (see Route without Jev) and say nothing about the key or the status. If it prints `{"error":"..."}` (any other failure, such as Jev answering 401 or 500), route by yourself and say the router was unavailable.
