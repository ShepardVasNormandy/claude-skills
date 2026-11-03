# Choosing visuals

Use a visual when it makes the point faster than a sentence. Every slide does not need one. Use at most one main visual per slide.

| Point to make | Visual | Notes |
|---|---|---|
| One number that sets the scene ("1,240 refunds a week handled by hand") | Big number with a one-line caption | Add the period and the source. |
| Change over time (order volume, error rate, refund backlog) | Line chart | Time on the x axis. Start the y axis at zero for counts. Mark the event that matters. |
| Comparing amounts across a few categories (cost per option, effort per team) | Horizontal bar chart | Sort bars by value. Label the values on the bars. |
| Parts of a whole with 2 to 4 parts | Stacked bar | Avoid pie charts with more than 3 slices. |
| Options against criteria | Comparison table | Rows are options, columns are criteria. Use short words or ratings in cells. Highlight the recommended row. |
| Two-axis trade-off (effort against impact, cost against risk) | 2x2 matrix | Name both axes and their direction. Place each option as a labelled dot. |
| Risks | Table with likelihood, impact, mitigation; or a likelihood-impact grid | Use the grid when there are more than 5 risks. |
| How components interact during one flow (checkout, refund) | Sequence diagram | Keep to the 4 to 6 participants that matter. |
| How systems connect | Box-and-arrow diagram (flowchart) | Group by ownership or deployment. Highlight what changes. |
| Entity lifecycle (order states) | State diagram | Only the states the decision affects. |
| Data model change | Small ER diagram | New tables in a highlight colour, existing ones in grey. |
| Rollout plan | Timeline or Gantt-style bars | Show phases, checkpoints and the rollback point. |
| Before and after | Two panels side by side | Same scale and layout on both sides. |

## Rules

- Each chart has a title that states the takeaway, labelled axes with units, and a source line.
- Use one accent colour for the recommended option or the change, and neutral colours for the rest.
- Do not use 3D charts, dual y axes or decorative icons.
- Draw diagrams with Mermaid or inline SVG so they stay sharp and editable. See the `rfc` skill's `references/mermaid.md` for Mermaid syntax.
- If the source has no data for a chart, do not invent it. Use a table of what is known, or list it as an open question.
