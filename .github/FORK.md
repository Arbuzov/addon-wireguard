# Working in this fork

This fork tracks [hassio-addons/app-wireguard][upstream] and adds features on
top. It is installed in Home Assistant as a **custom repository**, which
changes two things compared to upstream and drives everything below:

- Home Assistant reads `wireguard/config.yaml` straight off the default
  branch, so the `version:` in that file *is* the version users see.
- The images come from this fork's own registry namespace
  (`ghcr.io/arbuzov/wireguard/{arch}`), published by
  [`deploy.yaml`](workflows/deploy.yaml) on every push to `main`.

## Versioning

The fork runs its own `1.x.y` line, deliberately decoupled from upstream's
`0.x` releases — upstream keeps `version: dev` on its default branch and
stamps real versions only at release time, which a custom repository cannot
use.

| Change | Bump |
| --- | --- |
| New feature | MINOR — `1.2.0` → `1.3.0` |
| Fix, or merging upstream commits | PATCH — `1.2.0` → `1.2.1` |

Bump `wireguard/config.yaml` **in the same pull request as the change**.
Nothing else needs editing: `deploy.yaml` reads the version from there and
tags the image with it, and a release (if you cut one) must be tagged
`v<that same version>` or the deploy fails loudly.

Forgetting the bump is the failure this setup is shaped around, because it is
invisible: the new image reaches the registry, Home Assistant compares two
identical version strings, decides there is nothing to do, and keeps running
the old one. Nothing errors. Two things stop it:

- [`version-guard.yaml`](workflows/version-guard.yaml) fails any pull request
  that touches `wireguard/` without raising the version. Early feedback, but
  it only ever sees pull requests.
- [`deploy.yaml`](workflows/deploy.yaml) repeats the check at publish time and
  refuses to build. No ordinary push gets past it, a push straight to `main`
  included, and it rejects `version: dev` outright on every event, so a merge
  that drags upstream's placeholder back in cannot ship either. The only ways
  through are the two deliberate ones below.

Publishing is judged against the tip the push replaced, not the previous
commit, so a push carrying several commits is measured by its net effect.
Force-push the default branch and that tip is gone, taking with it any way to
tell which version was last published — so the deploy fails rather than
guessing. Re-run it from the Actions tab (`workflow_dispatch`) once the branch
is where you want it. A release and a manual run skip the comparison for the
same reason: both deliberately republish a version that already exists. The
`dev` rejection still applies to every one of them.

## Two tracks: fork and upstream

Features are developed here and offered upstream separately. The two tracks
never share a branch, because a branch aimed at upstream must not carry
anything fork-specific.

**Fork track** — branch off `main`, and bump the version:

```bash
git switch -c feat/my-feature main
# ...change, bump wireguard/config.yaml...
gh pr create --base main
```

**Upstream track** — branch off the `upstream` mirror branch (kept current by
[`sync-upstream.yaml`](workflows/sync-upstream.yaml)), and port only the
feature itself:

```bash
git fetch origin
git switch -c feat/my-feature-upstream origin/upstream
git checkout main -- <the files the feature touches>
# ...drop every fork-only edit listed below, leave version: dev alone...
gh pr create --repo hassio-addons/app-wireguard --base main
```

Nothing fork-specific may appear in an upstream branch:

| Fork-only | |
| --- | --- |
| `repository.yaml` | declares the custom repository |
| `.github/FORK.md` | this file |
| `.github/release-drafter.yml` | |
| `.github/workflows/deploy.yaml` | publishes to this fork's namespace |
| `.github/workflows/sync-upstream.yaml` | |
| `.github/workflows/version-guard.yaml` | |
| `wireguard/config.yaml` → `image:` | points at this fork's images |
| `wireguard/config.yaml` → `version:` | upstream keeps `dev` |

Everything else — the app itself, its docs, its tests, and the CI jobs that
run them — is meant to be portable, so keep it that way when you touch it.

[upstream]: https://github.com/hassio-addons/app-wireguard
