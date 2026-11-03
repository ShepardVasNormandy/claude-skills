# Side-effect patterns

External side effects are actions the database cannot roll back: sending an email, charging or refunding a card, booking a shipment, calling a partner's webhook. Each pattern lists what goes wrong, how to check for it in a review, and how to fix it. Examples use an online store.

## 1. Side effect before the record

**What goes wrong.** The handler sends the "Your refund is on its way" email, then writes the refund row. The write fails on a constraint. The customer got an email for a refund that does not exist.

**How to check.** In the changed code, find each side effect and the write that records it. Which comes first? What state is left if the process dies between them?

**How to fix.** Write an intent record first with a status such as `pending`. Perform the side effect. Update the record to `sent` or `failed` with the provider's reference.

```ts
const intent = await emails.createIntent({ orderId, template: 'refund_issued', status: 'pending' });
const res = await mailer.send(intent.payload, { idempotencyKey: intent.id });
await emails.markSent(intent.id, res.messageId);
```

## 2. Side effect inside the transaction

**What goes wrong.** A shipment is booked with the carrier inside the transaction that marks the order `shipped`. The commit then fails. The carrier will pick up a parcel for an order the store thinks is still `paid`.

**How to check.** Look for side-effect calls inside `transaction(...)` blocks.

**How to fix.** Commit the intent in the transaction. Perform the side effect after commit, from the same request or from an outbox worker.

## 3. No idempotency key sent to the provider

**What goes wrong.** A refund request to the payment provider times out and the worker retries. Without a key, the provider sees two independent refunds and pays out twice.

**How to check.** For each provider call that moves money or creates something, check whether an idempotency key is passed, and whether it is stable across retries (derived from the intent ID so every attempt sends the same key).

**How to fix.** Pass the intent record's ID as the provider's idempotency key. Most payment and email providers support this; check their documentation for how long keys are remembered.

## 4. Unknown outcome dropped on the floor

**What goes wrong.** A charge call times out. The code logs an error and moves on. The intent stays `pending` forever, and nobody knows whether the customer was charged.

**How to check.** Find the timeout and 5xx branches for each side effect. What state is the intent left in? Does anything ever look at it again?

**How to fix.** Leave the intent in `pending` or `unknown`, and have a reconciliation job (pattern 6) resolve it by querying the provider.

## 5. Webhook handled as the only source of truth

**What goes wrong.** The store waits for the provider's `refund.succeeded` webhook to mark refunds complete. A webhook is lost during a deploy, so the refund stays pending in the store although the customer has the money.

**How to check.** If the flow depends on webhooks, is there a fallback that polls the provider for intents older than a threshold? Are webhook handlers idempotent and tolerant of out-of-order delivery?

**How to fix.** Treat webhooks as a fast path. Back them with reconciliation. Verify webhook signatures, deduplicate by event ID, and apply state changes only when they move forward (`pending` to `succeeded` is allowed, `succeeded` back to `pending` is ignored).

## 6. No reconciliation

**What goes wrong.** Small mismatches pile up: shipments booked twice, emails marked sent that bounced, refunds the provider rejected after accepting. Nothing compares the store's records with the provider's.

**How to check.** Ask: for this side effect, what job finds intents stuck in a non-final state, and what job compares totals or records with the provider's report?

**How to fix.** Add a scheduled job that:
- selects intents in `pending` older than N minutes and queries the provider by idempotency key;
- updates them to the real outcome;
- alerts when an intent cannot be resolved or when daily totals differ from the provider's settlement report.

## 7. Customer notification tied to the wrong event

**What goes wrong.** "Your order has shipped" is sent when the label is created. The carrier never collects the parcel, and the customer chases a tracking number that never moves.

**How to check.** For each notification, find which state change triggers it. Is that the event the customer cares about, and is it confirmed?

**How to fix.** Trigger notifications from confirmed state changes (carrier scan received, provider confirmed refund). Make the notification itself idempotent per order and event type, so a replayed event does not send it again.

```sql
CREATE UNIQUE INDEX ON email_intents (order_id, template);
```

## 8. Compensation not defined

**What goes wrong.** A multi-step flow (reserve stock, charge, book shipment) fails at step three. Stock stays reserved and the customer stays charged, with no path to undo.

**How to check.** For each step after the first, ask what must be undone if this step fails for good, and whether the code or a runbook does it.

**How to fix.** Define a compensating action for each step (release reservation, refund charge) and trigger it when a later step reaches a permanent failure. Record each compensation as its own intent so it is idempotent and reconcilable.
