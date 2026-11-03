# UX checklist

Each pattern lists what goes wrong, how to check for it in a review, and how to fix it. Examples use an online store: customers placing orders and asking for refunds, and staff managing orders, refunds, inventory and customer emails.

## 1. Designing for an unnamed user

**What goes wrong.** A refund screen is built around the database model (line items, payment intents, ledger entries). Support staff, who need to answer "how much do I give back and when will the customer see it", have to translate it in their heads.

**How to check.** Find the user types in the repo's docs or the request. For each screen, ask which user it is for and what they need to decide or finish there. If the answer is "everyone", look again.

**How to fix.** Lead with the user's question. For support staff: amount to refund, method, when it arrives, what the customer will be told. Move technical detail behind a "Details" disclosure.

## 2. Main flow longer than it needs to be

**What goes wrong.** Issuing a full refund takes five screens: open order, choose "Refund", choose lines, confirm amount, confirm again. Most refunds are full refunds.

**How to check.** Write the flow as numbered steps. Mark each step as a decision the user must make or a step the system could infer. Count how often the common case takes the long path.

**How to fix.** Make the common case the default (all lines selected, full amount filled in) and keep partial refunds one click away.

## 3. Edge cases left out of the design

**What goes wrong.** The order summary is designed with a two-word product name and three line items. Real orders have 40 lines, 120-character product names, mixed currencies and items already partly refunded.

**How to check.** For each screen, try: zero items, one item, many items, very long text, missing optional fields, a value in another currency or locale, a user who leaves midway and comes back, and a user acting on stale data (the order was cancelled in another tab).

**How to fix.** Define truncation and wrapping rules, pagination or grouping for long lists, and what to show for missing data. Show already-refunded amounts so the user cannot refund twice.

## 4. Irreversible action with weak safeguards

**What goes wrong.** "Cancel order" sits next to "Edit order", looks the same, and runs immediately. It also emails the customer and releases stock, which the button does not mention.

**How to check.** List every action that deletes, sends, charges, refunds, cancels or notifies someone outside the team. For each one ask: is the consequence stated? Is it visually distinct? Is there a confirmation sized to the risk, or an undo? Can it fire twice?

**How to fix.**
- State the consequence in the confirmation: "Cancel order #1042? The customer will get a cancellation email and the 3 items go back into stock."
- Name the button after the action ("Cancel order"). Generic labels such as "OK" or "Yes" hide what will happen.
- For low-risk reversible actions, act at once and offer undo for a few seconds.
- For high-risk actions (bulk refunds, deleting a product with order history), require typing a value or a second explicit step, and show who and how many are affected.
- Keep destructive buttons away from frequent ones and style them as destructive.

## 5. Errors the user cannot recover from

**What goes wrong.** A customer submits a return request with a photo that is too large. The page reloads with "Error 413" and the form is empty.

**How to check.** For each input and action, list what can go wrong (invalid input, file too large, network loss, conflict, permission). Check whether the design prevents it, and what the message says when it happens. Does the user keep their work?

**How to fix.** Prevent where possible: state limits up front ("JPG or PNG, up to 10 MB"), use pickers for constrained values, validate inline after the user leaves a field. When an error happens, say what happened and what to do, in the user's words, next to the problem: "This photo is 14 MB. Choose one under 10 MB, or take a new photo at a lower resolution." Keep everything else they entered.

## 6. Missing states

**What goes wrong.** The "My orders" page was designed only with orders present. New customers see a blank page. When the order service is slow, they see nothing for several seconds and click away.

**How to check.** For every screen, check each state:

| State | Question |
|-------|----------|
| Loading | Does the user see that something is happening, and roughly where content will appear? |
| Empty, first use | Does it explain what will appear here and how to get started? |
| Empty, after filtering | Does it say no results match and offer to clear filters? |
| Partial | What if some data loaded and some failed? |
| Error | Does it say what failed and offer a retry or alternative? |
| Success | Does the user see that the action worked and what happens next? |
| No permission | Does it say why the user cannot see or do this, and who can help? |
| Offline or slow | Is the user's work kept? |

**How to fix.** Add the missing states to the design with real copy. "You have no orders yet. When you buy something, you can track it here." with a link to the shop.

## 7. Inconsistent or vague wording

**What goes wrong.** The same thing is called "return", "refund request" and "RMA" on three screens. The button says "Submit". An error says "Invalid input".

**How to check.** List the nouns and verbs used for each concept across the flow, including emails and notifications. Read every button label alone and ask if it says what will happen. Read every error and ask if the user knows what to do next.

**How to fix.** Pick one term per concept, ideally the one users already use, and use it everywhere. Label buttons with verb and object: "Request refund", "Send tracking email". Rewrite errors as cause and action: "The discount code SUMMER has expired. Remove it to continue, or try another code."

## 8. Accessibility gaps in the design

**What goes wrong.** Order status is shown only by a coloured dot. The return form's fields have placeholder text and no labels. The "Remove item" control is a 16-pixel icon.

**How to check.** Review the design for: text and control contrast (4.5:1 for body text, 3:1 for large text and UI parts), meaning carried by colour alone, visible labels for every field, a logical reading and focus order, touch targets at least 24 by 24 CSS pixels (44 recommended), and motion that cannot be turned off. If the change is built, try it with the keyboard only.

**How to fix.** Add text to colour cues ("Paid", "Refund pending"). Use visible labels above fields. Enlarge targets. Specify focus order and focus styles in the design handoff.

## 9. Novice and expert pass

**What goes wrong.** The bulk refund tool works well for the operations lead who processes 200 refunds a week, but a part-time support agent who uses it once a month cannot find the partial refund option and refunds the full amount. Or the reverse: a guided wizard helps newcomers but forces daily users through five steps every time.

**How to check.** Walk the main flow twice and write down each step.

- **Expert** (uses it daily, knows the terms, wants speed): Can they act in bulk? Are there keyboard shortcuts or remembered choices? Do confirmations get in the way of safe, frequent actions? Can they see the result without opening each item?
- **Novice** (new to it or uses it rarely, has forgotten the details, worries about mistakes): Are labels self-explanatory without training? Are defaults safe? Is help available at the point of need? Can they tell what will happen before committing?

Note where each one stalls, guesses or could make a costly mistake.

**How to fix.** Keep the safe, guided path as the default and add speed for experts on top: bulk selection, shortcuts, saved filters, "don't ask again" only for low-risk confirmations. Never remove the safeguard on high-risk actions for anyone.
