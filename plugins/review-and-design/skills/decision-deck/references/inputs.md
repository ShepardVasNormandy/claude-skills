# Getting facts from each input

Each input produces source notes. The deck is built only from them.

## Source notes format

```markdown
## Decision asked
- <one sentence> [source: <location>]

## Facts
| # | Topic | Fact | Quote | Location |
|---|---|---|---|---|
| F1 | context | Refunds are handled by hand when an order has more than one line | "multi-line orders cannot be partially refunded today" | docs/rfc/partial-refunds.md, Context |

## Gaps
- <topic the outline needs that the source does not cover>

## Conflicts
- <two places in the source that disagree, with both locations>
```

Topics follow the outline: decision, context, goals, non-goals, options, trade-offs, recommendation, design, risks, cost, rollout, open questions.

## Quoting sources

- Quote the shortest exact span that supports the fact, in double quotes. Do not paraphrase inside quotes.
- Give a location a reader can find: file path and section heading, Notion page title and heading, or "interview, answer to question 4".
- Keep numbers exactly as written, with their unit and period. If you convert a unit or sum numbers, mark the fact as derived and show the calculation.
- When you infer something the source does not state, write it as a separate fact with the location "inference" and say what it is based on.
- When two parts of the source disagree, list both under Conflicts and ask the user which one holds.

## Local RFC file

1. Read the whole file, and any file it links to inside the repo if it matters for the decision.
2. Map its headings to the outline topics. RFCs often call the recommendation "Proposal" and the options "Alternatives".
3. Use the file path and heading as the location.
4. If the RFC cites code, you may read that code to confirm a claim, and note it as a second location.

## Pasted RFC

1. Treat the pasted text as the only source. Do not fill gaps from general knowledge.
2. Use the nearest heading as the location. If there are no headings, use "pasted text, paragraph N".
3. If the paste looks cut off (it ends mid-sentence or a section is announced but missing), ask the user for the rest before going on.

## Notion page

1. Fetch the page with the Notion MCP. Fetch child pages and linked database rows only if they hold options, costs or risks.
2. Read comments only if the user asks; they record discussion and rarely hold the decision.
3. Use the page title and heading as the location, and keep the page URL for the appendix.
4. Note the page's last edited time in the source notes so the user can see whether it is current.

## Interview

Ask one question per message, in this order, and skip what the user already answered:

1. What decision do you need from the board, in one sentence?
2. Why now? What happens if the board decides nothing?
3. What options did you consider, including doing nothing?
4. Which option do you recommend, and what are the two or three deciding reasons?
5. What are the biggest risks, and what reduces each one?
6. What does it cost in people, time and money? Where do those numbers come from?
7. How would you roll it out, and how would you roll it back?
8. What is still open?

Record each answer as facts with the location "interview, answer N". At the end, read the source notes back to the user and ask them to correct them before you build the deck.
