# LatentBuild Installer

Public bootstrap surface for installing the LatentBuild CLI without requiring
access to the private LogicLegion application repository.

## Install

From any directory:

```bash
curl -fsSL https://raw.githubusercontent.com/asimore/latentbuild-install/main/install.sh | sh
```

From a customer repo, with local readiness check:

```bash
cd /path/to/customer-repo
curl -fsSL https://raw.githubusercontent.com/asimore/latentbuild-install/main/install.sh | sh -s -- --repo-root "$PWD"
```

Then enroll the repo locally:

```bash
lb-enroll-local "$PWD" <repo-id>
```

## What It Does

- downloads the pinned `latentbuild` wheel from this repo's GitHub Release
- verifies the wheel SHA-256
- installs with `pipx` when available, otherwise a dedicated user venv at
  `~/.latentbuild/venv`
- verifies `lb --help`
- optionally runs `lb doctor`

## What It Does Not Do

- does not require the private LogicLegion source checkout
- does not write to a customer repo during install
- does not push, create PRs, merge, deploy, or publish
- does not request production secrets or OAuth credentials
- does not use hosted persistence or mutate shared customer state

## Release

Current release:

```text
v1.0.1
```

Wheel:

```text
latentbuild-1.0.1-py3-none-any.whl
```

SHA-256:

```text
361614f3d5cace55d0c384ed7c97464c456bf799cbb5f8f5b1e44a9f628c37eb
```
