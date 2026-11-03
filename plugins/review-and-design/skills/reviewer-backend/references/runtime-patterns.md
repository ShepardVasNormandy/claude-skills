# Runtime patterns

Each pattern lists what goes wrong, how to check for it in a review, and how to fix it. Examples use an online store with orders, refunds, inventory and emails.

## 1. Non-idempotent write endpoint

**What goes wrong.** A client retries `POST /orders` after a network timeout. The first request did succeed, so the customer now has two orders and two reservations.

**How to check.** For each create or state-changing endpoint, ask what the server does when it receives the exact same request twice. Look for an idempotency key header, a natural unique key, or a check of existing state.

**How to fix.** Accept an `Idempotency-Key` from the client, store it with a unique constraint alongside the result, and return the stored result on a repeat.

```sql
CREATE UNIQUE INDEX ON orders (customer_id, idempotency_key);
```

## 2. Non-idempotent message handler

**What goes wrong.** Most queues deliver at least once. A `refund.approved` message is redelivered after a consumer crash, and the refund is sent to the provider twice.

**How to check.** For each consumer, find what makes a second delivery a no-op. Assume redelivery even when the broker claims exactly-once delivery.

**How to fix.** Record processed message IDs in a table with a unique constraint, inside the same transaction as the handler's writes. Or make the write conditional on state (`WHERE status = 'approved'`) so the second run changes nothing.

## 3. Lost update

**What goes wrong.** Two workers read the same inventory row (`available = 5`), each subtracts 3, and both write `2`. Six units were sold from a stock of five.

**How to check.** Look for read, modify in application code, then write. Any row that more than one request can change at the same time is at risk.

**How to fix.** Pick one:
- an atomic update with a guard: `UPDATE inventory SET available = available - 3 WHERE sku = $1 AND available >= 3`, and check the row count;
- optimistic versioning: `UPDATE ... SET version = version + 1 WHERE id = $1 AND version = $2`, retry or fail on zero rows;
- `SELECT ... FOR UPDATE` inside a short transaction when the logic cannot be expressed in one statement.

## 4. Duplicate creation race

**What goes wrong.** "Check if a refund exists for this order line, create it if not" runs in two requests at once. Both checks pass and two refunds are created.

**How to check.** Find "if not exists then insert" in application code. Is there a database constraint behind it?

**How to fix.** Add a unique constraint on the business key (`refunds (order_line_id)` for a one-refund-per-line rule) and handle the constraint violation as "already done".

## 5. Missing or infinite timeout

**What goes wrong.** An HTTP client has no timeout. A slow shipping-rate provider holds request threads until the service stops responding to everything.

**How to check.** Find every outbound client construction and call. Is there a connect timeout and a total timeout? Is the total below the caller's own deadline?

**How to fix.** Set explicit timeouts on every client. Keep the budget smaller than the inbound request timeout so the service can still respond with an error.

## 6. Timeout treated as failure

**What goes wrong.** The call to capture a payment times out. The code marks the order `payment_failed` and lets the customer retry. The first capture actually went through, so the customer pays twice.

**How to check.** Look at the `catch` around each outbound call that changes something remotely. Does a timeout take the same branch as a definite rejection (HTTP 4xx, declined)?

**How to fix.** Treat a timeout as unknown. Move the record to a `pending_confirmation` state, then query the provider by your idempotency key or wait for its webhook before deciding. Only definite rejections are failures.

## 7. Retries without backoff, limits or idempotency

**What goes wrong.** A handler retries immediately in a tight loop when the email provider returns 503. It hammers the provider, gets rate limited, and if the sends were not idempotent, customers receive several copies.

**How to check.** Find retry loops and queue retry settings. Is there exponential backoff with jitter? A maximum attempt count? Is the retried operation idempotent?

**How to fix.** Retry only idempotent operations, with exponential backoff, jitter and a cap. After the cap, move the message to a dead-letter queue and alert.

## 8. Poison message blocks the queue

**What goes wrong.** One malformed `order.created` message throws on every attempt. With ordered processing, every message behind it is stuck.

**How to check.** What happens when a handler throws on a message forever? Is there a dead-letter queue and a maximum delivery count?

**How to fix.** Configure a delivery limit and a dead-letter queue. Distinguish permanent errors (bad payload, unknown order) from transient ones and send permanent errors straight to the dead-letter queue.

## 9. A new path with no signals

**What goes wrong.** A new refund flow ships. A week later support reports refunds that never arrived, and nobody can tell from logs whether the job ran for those orders.

**How to check.** For the new path, ask: can I find all log lines for one order ID? Is there a counter for success and failure? Does the trace connect the HTTP request to the worker that processed it?

**How to fix.** Log at each decision point with structured fields (`order_id`, `refund_id`, `outcome`) so the lines can be filtered by entity. Emit `refunds_processed_total{outcome}` and a latency histogram. Propagate trace context through queue messages. Do not log card numbers, full addresses or tokens.

## 10. Tests that only cover the happy path

**What goes wrong.** Tests confirm that a refund is created. Nothing tests the duplicate message, the provider timeout or the concurrent cancel, so those paths break silently.

**How to check.** For each forced check that applies, look for a test that exercises the failure and asserts the resulting state.

**How to fix.** Add tests that deliver the same message twice and assert one provider call, run two updates concurrently and assert one wins, stub a timeout and assert the record is left pending, and call as another tenant and assert 404.
