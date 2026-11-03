# Architecture patterns

Each pattern lists what goes wrong, how to check for it in a review, and how to fix it. Examples use an online store with orders, refunds, inventory and emails.

## 1. Transaction too narrow

**What goes wrong.** Two writes that belong together are committed separately. If the process dies between them, the data is left half-updated. An order is marked `paid` but the inventory reservation is never converted, so stock counts drift.

**How to check.** List every write in the changed function. For each pair, ask whether one without the other is a valid state. Look for repository calls that each open and commit their own transaction.

**How to fix.** Wrap the writes in one unit of work and pass the transaction handle down.

```ts
await db.transaction(async (tx) => {
  await orders.markPaid(tx, orderId);
  await inventory.commitReservation(tx, orderId);
});
```

## 2. Transaction too wide

**What goes wrong.** A network call runs while a transaction holds locks. A slow payment provider keeps rows locked for seconds, connection pools run dry, and a rollback after the call succeeded leaves the customer charged with no record.

**How to check.** Inside every `transaction(...)` block, look for HTTP clients, queue publishers, email senders, file uploads or `await` on anything that is not the database.

**How to fix.** Do the database work, commit, then perform the call. If the call must be guaranteed, write an outbox row inside the transaction and let a worker perform the call (see pattern 3).

## 3. Dual write without an outbox

**What goes wrong.** The code commits a row and then publishes an event. If the publish fails or the process crashes, consumers never learn about the change. The reverse order publishes an event for a row that was rolled back.

**How to check.** Find any `publish`, `emit`, `enqueue` or webhook call right after a commit. Ask what happens if the process dies on the line between them.

**How to fix.** Insert an `outbox` row in the same transaction as the business write. A relay reads unsent outbox rows, publishes them, and marks them sent. Consumers must be idempotent because the relay can publish twice.

```sql
INSERT INTO refunds (id, order_id, amount_cents, status) VALUES ($1, $2, $3, 'requested');
INSERT INTO outbox (id, topic, payload) VALUES ($4, 'refund.requested', $5);
```

## 4. Schema change that breaks running code

**What goes wrong.** A column is renamed or made `NOT NULL` in the same deploy as the code that uses it. During the rollout, old instances still write the old shape and fail.

**How to check.** For every migration, ask whether the previous release of the code still works against the new schema, and whether the new code works against the old schema if the migration runs late.

**How to fix.** Use expand and contract. Add the new column as nullable, deploy code that writes both, backfill, switch reads, then drop the old column in a later release.

Example: renaming `orders.ship_addr` to `orders.shipping_address_id` takes three separate deploys.

## 5. Backfill that cannot resume

**What goes wrong.** A single `UPDATE` touches millions of rows, locks the table, and times out halfway. Rerunning it from the start repeats work or double-applies a transformation.

**How to check.** Look at the backfill script or migration. Is it batched? Does it record progress? Is each batch idempotent (safe to run twice on the same rows)?

**How to fix.** Process by primary key range in small batches, commit per batch, and make the update conditional on the old state.

```sql
UPDATE orders SET currency = 'USD'
WHERE id > $last_id AND id <= $last_id + 1000 AND currency IS NULL;
```

## 6. Authorization in the wrong layer

**What goes wrong.** The route checks that the user is logged in, but the service loads `refunds.findById(id)` without checking that the refund belongs to the user's store. Anyone who can guess or enumerate an ID can read or act on another customer's data.

**How to check.** Trace each handler from the route to the data access. Find where the resource's owner or tenant is compared to the caller. If the only check is in the UI or in a middleware that only verifies authentication, it is missing.

**How to fix.** Scope queries by the caller's tenant, or load the resource and assert ownership in the service before acting. Return 404 for resources the caller may not see, so IDs do not leak existence.

```ts
const refund = await refunds.findOne({ id, storeId: caller.storeId });
if (!refund) throw new NotFound();
```

## 7. State held in a status string with no transition rules

**What goes wrong.** Any code path can set `order.status` to anything. A refund handler sets `refunded` on an order that was never paid, or a late webhook moves a `cancelled` order back to `shipped`.

**How to check.** Search for every write to the status column. Is there one place that decides which transitions are legal?

**How to fix.** Define allowed transitions in one function and make the update conditional on the current state.

```sql
UPDATE orders SET status = 'shipped' WHERE id = $1 AND status = 'paid';
```

Check the affected row count. Zero rows means the transition was not allowed or someone else got there first.
