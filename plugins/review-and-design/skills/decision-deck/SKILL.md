---
name: decision-deck
description: Builds a short decision deck for an architecture review from an RFC file, a pasted RFC, a Notion page or an interview. Extracts the decision being asked, the options and trade-offs, the recommendation, risks, cost and rollout, checks every claim against the source, and presents the deck as slides in an Artifact when that tool is available, otherwise as one HTML page. Use when the user needs to present a design or tech choice to a board, a review committee or leadership for a decision.
---

# Decision deck

Turn a design proposal into a deck of about 8 to 12 slides that gets a decision in one meeting. The board should know from the first slide what it is asked to decide.

## Step 1: Pick the input

Ask the user which input to use if they did not say:

1. **Local RFC file.** A path in the repo, for example `docs/rfc/partial-refunds.md`.
2. **Pasted RFC.** Text the user pastes into the chat.
3. **Notion page.** A URL or page title.
4. **Interview.** No document yet. You ask the questions.

For a Notion page:

Requires: Notion MCP, for the Notion input only. If its tools are not available, tell the user which server is missing and how to add it (`claude mcp add` with the Notion MCP server, or a plugin that ships it), offer the other three inputs, and if the user still wants Notion, then stop.

## Step 2: Extract the facts

Follow `references/inputs.md` for the chosen input. The result is a set of source notes: each fact with its source quote and location. Nothing goes in the deck that is not in the source notes or marked as your own inference.

For a long source (over about 3,000 words, or several linked documents) you may hand the reading to a sub-agent with the brief in `references/agents/source-reader.md`. Give it the source path or text and the source notes format. Check its source notes against the source on two or three points before you use it.

If the source does not state the decision being asked, ask the user before you go on. A deck without a clear ask is not useful.

Show the gaps in the source notes to the user (for example "no cost estimate", "no rollback plan") and ask whether to fill them, mark them as open questions, or drop the slide.

## Step 3: Build the deck

Use the outline in `references/outline.md`. Pick visuals with `references/slide-visuals.md`. Rules:

- One idea per slide. The slide title states the point as a sentence ("Option B halves refund handling time").
- At most about 40 words of body text per slide, outside tables and diagrams.
- Numbers keep their unit and their source.
- Put the recommendation on its own slide. Present options fairly before it.
- Move detail the board may ask about to the appendix.

## Step 4: Check every claim

Before showing the deck, check each claim on every slide against the source notes and the source. You may use a sub-agent with the brief in `references/agents/claim-checker.md` for this. Fix or remove every claim marked unsupported or contradicted. Mark inferences as such on the slide or in the speaker notes.

## Step 5: Output

- If an Artifact tool is available, publish the deck as a Slides artifact. Run its quickstart with intent `slides` first and follow what it returns.
- Otherwise write one self-contained HTML file, for example `<slug>-deck.html`, next to the source or in the current directory. Inline all CSS and JavaScript, with no network requests. Show one slide at a time with arrow-key navigation, and add a print stylesheet that puts one slide per page so it can be saved as PDF.

Put speaker notes with the source references for each slide in the notes field, or in a hidden `<aside>` per slide in the HTML file.

## Step 6: Hand over

Give the user the link or file path, the slide count, and the list of open questions and gaps that are in the deck. Offer to tighten any slide.
