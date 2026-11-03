# Logging guidelines

This is a template. Copy it into your repository, change what does not fit your stack, and point the `logging_guidelines` config key at your copy.

## 1. Format: structured JSON

Every log line is one JSON object on one line, written to stdout. The platform collects it.

Required fields on every line:

| Field | Meaning |
|---|---|
| `timestamp` | RFC 3339 in UTC, with milliseconds: `2026-03-14T09:26:53.589Z` |
| `level` | `debug`, `info`, `warn` or `error` |
| `message` | Short constant phrase, see section 6 |
| `service.name` | Service that wrote the line, for example `order-service` |
| `deployment.environment.name` | `production`, `staging` or `development` |
| `trace_id`, `span_id` | When a trace is active, see section 4 |

Human-readable output is fine on a developer's machine. Switch on it with configuration, never in code.

## 2. Levels

| Level | Use it when | Examples | Default in production |
|---|---|---|---|
| `debug` | Detail that helps while developing or chasing one bug | Computed shipping rates for each carrier, cache key used | Off |
| `info` | A normal business event or lifecycle step that someone may want to find later | Order placed, refund issued, worker started | On |
| `warn` | Something unexpected happened, but the request still succeeded or will be retried | Payment provider timed out and the retry worked, stock fell below the reorder level | On |
| `error` | A request, job or message failed and needs attention | Refund rejected by the provider, inventory sync job crashed | On, and alerts may fire |

Rules:

- A client mistake (validation error, 404) is `info`, or `warn` if it repeats from the same client. Keep `error` for failures on your side.
- An `error` line must include the error type and message, and the stack trace when there is one.
- Log an error once, at the place that handles it. Code that rethrows adds context to the error and does not log it.
- Do not use `error` for something nobody will act on.

## 3. Field names

Use the [OpenTelemetry semantic conventions](https://opentelemetry.io/docs/specs/semconv/) when a name exists there. Dotted names are fine in JSON. Keep the same name for the same thing across services.

| What | Field |
|---|---|
| HTTP method, route, status | `http.request.method`, `http.route`, `http.response.status_code` |
| URL path | `url.path` (never the query string if it can hold tokens) |
| Duration | `duration_ms` (team convention; OpenTelemetry records durations on spans and metrics) |
| Error | `exception.type`, `exception.message`, `exception.stacktrace` |
| Database | `db.system.name`, `db.operation.name`, `db.collection.name` |
| Messaging | `messaging.system`, `messaging.destination.name`, `messaging.message.id` |
| Peer service | `server.address`, `server.port` |
| User | `user.id` (an internal id only) |

Domain fields use a `<entity>.<attribute>` prefix in the same style: `order.id`, `refund.id`, `refund.amount`, `shipment.carrier`, `product.sku`, `warehouse.id`.

## 4. Correlation

- Every service propagates W3C Trace Context (`traceparent` header) on incoming and outgoing HTTP calls and on queue messages.
- The logger adds `trace_id` and `span_id` from the active span automatically. Use the OpenTelemetry log bridge or appender for your logger instead of copying ids by hand.
- Background jobs start a new trace per job run, or per message when they process a queue, so each run can be found on its own.
- When a business id is the natural way to search (an order id in a support ticket), log it as a field on the relevant lines too.

## 5. What never to log

Never write these to logs at any level:

- Passwords, API keys, client secrets, private keys, session cookies.
- Access tokens, refresh tokens, JWTs, signed URLs, password reset and email verification links.
- Full card numbers, CVV, bank account numbers. Logging the last 4 digits and the card brand is fine.
- Personal data: names, email addresses, phone numbers, postal addresses, dates of birth, IP addresses where they count as personal data, free-text fields typed by customers (delivery notes, review text).
- Full request or response bodies from payment, identity or shipping providers.
- `Authorization`, `Cookie` and `Set-Cookie` headers.

Use internal ids instead: `customer.id`, `order.id`, `address.id`.

### Redaction

- Configure redaction once, in the logger setup, by field name and path (`*.password`, `*.token`, `headers.authorization`, `*.email`). Replace values with `[REDACTED]`.
- Do not log whole objects (`order`, `req`, `user`). Pick the fields you need. Redaction lists miss new fields.
- If you must keep a value to match events, log a keyed hash of it (HMAC with a secret), never the raw value.
- When a leak is found, treat it as an incident: fix the code, then purge or restrict the affected logs.

## 6. Message style

- The message is a short, constant phrase in lower case with no trailing period: `refund issued`, `stock reservation failed`.
- Keep values out of the message and put them in fields. Constant messages make logs easy to group and count.
- Use past tense for events that happened, and "failed" for failures.
- One event per line. Do not log "starting X" and "finished X" both, unless the step is long or often hangs; log the finish with `duration_ms`.

## 7. Sampling and volume

- Keep every `warn` and `error` line.
- Do not log per item inside a loop over many items. Log one summary line with counts: `{"message":"inventory sync finished","items.updated":1840,"items.failed":3}`.
- Sample high-volume `info` lines such as health checks or successful cache hits, for example 1 in 100, and log the rate as `sample.rate`.
- Prefer head-based trace sampling so a sampled request keeps all its lines together.
- Use metrics for things you only count or graph.

## 8. Examples

Good: order placed.

```json
{"timestamp":"2026-03-14T09:26:53.589Z","level":"info","message":"order placed","service.name":"order-service","deployment.environment.name":"production","trace_id":"<32 hex chars>","span_id":"<16 hex chars>","order.id":"ord_8f3k2","customer.id":"cus_19ab","order.total":"89.90","order.currency":"USD","order.line_count":3}
```

Bad: values in the message, personal data, no ids.

```json
{"level":"info","message":"Order placed by jane.doe@example.com for 89.90 USD shipping to 221B Example Street"}
```

Good: refund failed at the provider, handled here.

```json
{"timestamp":"2026-03-14T10:02:11.004Z","level":"error","message":"refund failed","service.name":"payment-service","deployment.environment.name":"production","trace_id":"<32 hex chars>","span_id":"<16 hex chars>","refund.id":"rf_77x","order.id":"ord_8f3k2","refund.amount":"25.00","server.address":"api.payments.example","http.response.status_code":402,"exception.type":"ProviderDeclined","exception.message":"insufficient_funds"}
```

Bad: the same failure logged at three layers, with the provider's token in the payload.

```json
{"level":"error","message":"error in refund client","payload":{"auth":"Bearer <provider secret>","amount":2500}}
{"level":"error","message":"refund service error"}
{"level":"error","message":"request failed"}
```

Good: retry that worked.

```json
{"timestamp":"2026-03-14T11:45:00.120Z","level":"warn","message":"carrier rate request retried","service.name":"shipping-service","deployment.environment.name":"production","trace_id":"<32 hex chars>","span_id":"<16 hex chars>","shipment.carrier":"courier-x","retry.attempt":2,"duration_ms":2310}
```

Bad: a loop that logs every product.

```json
{"level":"info","message":"updated stock for SKU-1001"}
{"level":"info","message":"updated stock for SKU-1002"}
```
