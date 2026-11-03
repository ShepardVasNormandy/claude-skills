# Data patterns

Each pattern lists what goes wrong, how to check for it in a review, and how to fix it. Examples use an online store admin with orders, refunds and inventory. Code samples use React with TanStack Query as one example. The same patterns apply to any data-fetching library's cache, so adapt the names to the library the repo uses.

## 1. Hardcoded query keys

**What goes wrong.** A mutation calls `invalidateQueries({ queryKey: ['orderList'] })` while the list was registered under `['orders', 'list', filters]`. The call matches nothing, returns without error, and the list stays stale.

**How to check.** Search the diff for string-literal cache keys in every call that reads, invalidates or writes the cache (in TanStack Query: `useQuery`, `useInfiniteQuery`, `invalidateQueries`, `setQueryData` and `cancelQueries`). Compare each to the key factory for that entity.

**How to fix.** Define one key factory per entity and use it everywhere.

```ts
export const orderKeys = {
  all: ['orders'] as const,
  list: (filters: OrderFilters) => [...orderKeys.all, 'list', filters] as const,
  detail: (id: string) => [...orderKeys.all, 'detail', id] as const,
};
```

## 2. Invalidating only the detail view

**What goes wrong.** Issuing a refund from an order drawer invalidates `orderKeys.detail(id)`. The drawer updates, but the order list behind it still shows the old status and total until a reload.

**How to check.** For each mutation, list every query that displays the changed entity: detail, lists, counts, related entities (a refund changes the order, the refunds list and maybe a dashboard total).

**How to fix.** Invalidate at the entity root when lists and details both show the data, and add related roots explicitly.

```ts
onSuccess: () => {
  queryClient.invalidateQueries({ queryKey: orderKeys.all });
  queryClient.invalidateQueries({ queryKey: refundKeys.all });
},
```

## 3. Server data copied into local state

**What goes wrong.** A component does `const [order, setOrder] = useState(data)` and edits the copy. When the query refetches, the copy does not update, and two sources of truth disagree.

**How to check.** Look for component state or a global store initialized from query data, or an effect that syncs query data into state (in React, `useState` or `useEffect`).

**How to fix.** Read from the query directly. Keep only true UI state (open panels, draft form values) locally. For forms, initialize the form library with the server values and reset it when the entity ID changes.

## 4. Double submit

**What goes wrong.** The "Issue refund" button stays enabled while the request runs. A slow network invites a second click, and two refunds are created.

**How to check.** For every button or form that triggers a mutation, check that it is disabled or ignored while `isPending`, and that pressing Enter in the form does not bypass the guard.

**How to fix.** Disable the control and show progress while pending. Send an idempotency key with the request so the server can deduplicate as well; the client guard alone is not enough.

```tsx
<Button type="submit" disabled={refund.isPending}>
  {refund.isPending ? 'Issuing refund…' : 'Issue refund'}
</Button>
```

## 5. Optimistic update with no rollback

**What goes wrong.** Marking an order as shipped updates the cache optimistically. The server rejects it because the order was cancelled. The UI keeps showing "Shipped".

**How to check.** For each optimistic write to the cache, look for a snapshot of the previous value, a rollback on error, and a refetch once the request settles (in TanStack Query: `onMutate`, `onError` and `onSettled`).

**How to fix.**

```ts
onMutate: async ({ id }) => {
  await queryClient.cancelQueries({ queryKey: orderKeys.detail(id) });
  const previous = queryClient.getQueryData(orderKeys.detail(id));
  queryClient.setQueryData(orderKeys.detail(id), (o) => ({ ...o, status: 'shipped' }));
  return { previous };
},
onError: (_err, { id }, ctx) => {
  queryClient.setQueryData(orderKeys.detail(id), ctx?.previous);
  toast.error('Could not mark the order as shipped. It may have been cancelled.');
},
onSettled: () => queryClient.invalidateQueries({ queryKey: orderKeys.all }),
```

Use optimistic updates only where the server almost always agrees and the change is easy to reverse. Money movements should wait for the server.

## 6. Client-side checks treated as security

**What goes wrong.** The "Refund" button is hidden for users without the `refunds:write` role. The endpoint does not check the role, so anyone can call it from the browser console.

**How to check.** For every permission check in the diff, find the matching check on the server. Search for secrets, API keys or other users' data in client code, environment variables exposed to the browser, and `dangerouslySetInnerHTML` or `v-html` on user-provided content.

**How to fix.** Keep the UI check for convenience and confirm the server enforces the same rule. Move secrets to the server. Sanitize any HTML from users with a maintained sanitizer before rendering it.

## 7. Server validation errors lost

**What goes wrong.** The server rejects a refund with `{ field: 'amount', message: 'Exceeds the amount paid' }`. The form shows a generic "Something went wrong" toast and clears the inputs.

**How to check.** Find the mutation's error handling. Does it read the server's error shape? Does it call the form library's `setError` for field errors? Are inputs preserved?

**How to fix.** Map field errors to fields and show the rest at the top of the form. Keep the values. Move focus to the first field with an error.

```ts
onError: (err) => {
  for (const e of err.fieldErrors ?? []) form.setError(e.field, { message: e.message });
  if (!err.fieldErrors?.length) setFormError(err.message);
},
```

## 8. Errors that never reach the reporter

**What goes wrong.** A render error in the inventory table shows a blank screen. Nothing is reported, so the team learns about it from a support ticket.

**How to check.** Is there an error boundary around the new screen? Do failed mutations and unhandled rejections reach the project's error reporter? Are expected errors (validation, 404, permission denied) filtered out so they do not drown real incidents?

**How to fix.** Wrap routes or major panels in an error boundary with a fallback that offers a retry. Report unexpected errors with context (route, entity ID, action), and strip personal data such as emails and addresses before sending.
