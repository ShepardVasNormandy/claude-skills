# Rendering patterns

Each pattern lists what goes wrong, how to check for it in a review, and how to fix it. Examples use an online store admin with orders, refunds and inventory. Code samples use React as one example; adapt them to the framework the repo uses.

## 1. Missing loading, error or empty state

**What goes wrong.** The refunds tab renders `data.map(...)`. While loading it shows nothing, on error it crashes, and with no refunds it shows a blank area the user reads as broken.

**How to check.** For each query the view uses, find the branch for `isPending`, `isError` and an empty result. Check that the empty state says what the user can do.

**How to fix.**

```tsx
if (refunds.isPending) return <TableSkeleton rows={5} />;
if (refunds.isError) return <ErrorState message="Could not load refunds." onRetry={refunds.refetch} />;
if (refunds.data.length === 0) return <EmptyState title="No refunds yet" body="Refunds you issue for this order appear here." />;
```

Keep the skeleton roughly the size of the content to avoid layout shift. For background refetches, keep showing the old data with a small indicator instead of returning to the skeleton.

## 2. Unneeded re-renders from unstable props

**What goes wrong.** A parent passes `filters={{ status }}` and `onSelect={() => ...}` to a memoized order table. Both are new objects on every render, so the table re-renders on every keystroke in an unrelated search box.

**How to check.** Use your framework's profiler (the React profiler, Vue devtools) or "highlight updates" to see what renders when you type. In code, look for object, array or function literals passed to memoized children or used in effect dependency arrays.

**How to fix.** Move state down to the component that uses it, so unrelated parts do not re-render. Memoize values passed to memoized children (`useMemo` and `useCallback` in React) only where profiling shows a cost. Split context providers so a change in one value does not re-render every consumer.

## 3. Large list rendered in full

**What goes wrong.** The inventory page renders 8,000 SKUs as table rows. Scrolling stutters and the page takes seconds to become interactive.

**How to check.** Can the list grow without bound? Does the diff render all items at once? Is there server-side pagination?

**How to fix.** Paginate on the server (cursor-based for lists that change often). If the user really needs one long scroll, virtualize the rows with a maintained library such as TanStack Virtual. Keep row components cheap and keyed by a stable ID such as the SKU. Array indexes break when rows are inserted or sorted.

## 4. Bundle growth

**What goes wrong.** A charting library or a full date library is imported into the order list, which is on the main route. Every user downloads it, even those who never open the analytics tab.

**How to check.** Look at new imports and `package.json` changes. Run the production build and compare chunk sizes with the base branch, or use the bundle analyzer the repo has.

**How to fix.** Lazy load heavy screens and dialogs with a dynamic `import()` (`React.lazy` in React). Import only the functions you need from large libraries. Prefer the platform (`Intl.DateTimeFormat`, `Intl.NumberFormat` for prices) over a new dependency.

## 5. Keyboard and focus

**What goes wrong.** The refund dialog opens, but focus stays on the page behind it. Tab moves through hidden page links. Closing the dialog drops focus to the top of the document, so a keyboard user loses their place in the order list.

**How to check.** Use the change with the keyboard only: Tab, Shift+Tab, Enter, Space, Escape, arrow keys in menus. Check that every control is reachable, the focus ring is visible, dialogs trap focus and return it to the trigger on close.

**How to fix.** Use the component library's accessible dialog, menu and combobox primitives. Do not build clickable `div`s; use `button` and `a`. Do not remove the focus outline without a visible replacement.

## 6. Missing labels and names

**What goes wrong.** The quantity field in the inventory form has a placeholder and no label. A screen reader announces "edit text". An icon-only trash button is announced as "button".

**How to check.** Inspect the accessibility tree in the browser devtools, or run an automated checker such as axe on the screen. Every input needs a label tied to it, and every icon-only control needs an accessible name.

**How to fix.**

```tsx
<label htmlFor="qty">Quantity in stock</label>
<input id="qty" type="number" aria-describedby="qty-help" />
<p id="qty-help">Counts units across all warehouses.</p>

<button aria-label="Delete order note"><TrashIcon aria-hidden /></button>
```

Associate error messages with the field through `aria-describedby` and set `aria-invalid` on the field.

## 7. Low contrast and colour-only meaning

**What goes wrong.** Order status badges use pale green and pale red text on white, and colour is the only difference between "Paid" and "Payment failed".

**How to check.** Measure contrast with devtools or a contrast checker: 4.5:1 for normal text, 3:1 for large text and UI components. Look for any state conveyed only by colour.

**How to fix.** Use the design system's tokens that meet AA. Add a text label or icon alongside colour.

## 8. Tests at the wrong level

**What goes wrong.** The refund form has a snapshot test and a unit test of a helper. Nothing checks that submitting shows the pending state, that a server error appears on the amount field, or that the order list updates afterwards.

**How to check.** For each forced check that applies, look for a test that renders the component, interacts as a user would (Testing Library queries by role and label), and asserts what the user sees. Check that the network is mocked at the request layer (for example with MSW) so the real hooks run.

**How to fix.**
- Component tests for states and interactions: loading, error, empty, pending, server field errors.
- An integration test for the riskiest flow that covers mutation and cache refresh together: issue a refund, close the drawer, assert the list shows the new status.
- End-to-end tests only for a few critical journeys, since they are slow and brittle.
- Drop snapshot tests that nobody reads when they change.
