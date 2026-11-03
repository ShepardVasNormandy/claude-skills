# Deciding what to do with an advisory

Go down the table and take the first row that fits.

| Situation | Decision | Notes |
|---|---|---|
| The vulnerable package is a direct dependency and a fixed version exists | Bump the direct dependency | Prefer the smallest version that fixes it. A major bump needs the changelog read and the tests run |
| A transitive dependency, and its current range already allows the fixed version | Refresh it in the lockfile | No `package.json` change. Only the lockfile moves |
| A transitive dependency, and a newer version of a parent pulls in the fix | Bump the parent | Pick the closest parent you control. Check the parent's changelog for breaking changes |
| A transitive dependency, a fix exists, and no parent release uses it yet | Add an override | Scope it to the parent when the package manager allows. Open an issue upstream or note when to remove it |
| No fixed version exists, or the fix breaks the app | Accept the risk | Needs a reason (why the code path is not reachable, or what limits the impact) and an expiry date at most 90 days out |
| The advisory is a false positive (wrong package, wrong version range) | Accept the risk | Reason: what makes it a false positive, with a link. Expiry date as above |

Before accepting a risk, ask the user. Do not accept one on your own.

When the expiry date comes, the scan fails again, and the decision is made a second time with the information available then.

## Examples

| Advisory | Package | Decision |
|---|---|---|
| `GHSA-xxxx-xxxx-xxxx` | `@acme/http-client` 2.3.0, direct | Bump to 2.3.4 |
| `GHSA-xxxx-xxxx-xxxx` | `follow-redirects`, under `axios` | Override `axios>follow-redirects` to ^1.15.6 |
| `GHSA-xxxx-xxxx-xxxx` | `semver`, under a build tool | Refresh in the lockfile. The range already allows 7.5.2 |
| `GHSA-xxxx-xxxx-xxxx` | `image-size`, dev only, no fix | Accept until 2027-02-01: only runs at build time on our own images |
