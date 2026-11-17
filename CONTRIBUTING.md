# Contributing #

Thanks for your interest! This repository holds the container build
scaffolding only — Prusa Connect itself is developed
[upstream](https://github.com/prusa3d/prusa-connect), and changes to the
application belong there.

## Development setup ##

Requirements: Docker (with BuildKit), [uv](https://docs.astral.sh/uv/), and
GNU make.

```sh
uv sync --group dev
uv run pre-commit install
make build          # build the image for your platform
make test           # run the pytest suite against it
make lint           # run every pre-commit hook
```

## How versioning works ##

`version.txt` holds the upstream Prusa Connect version this repository
builds, and container releases carry the same version. The flow is
automated:

- **Renovate** watches upstream releases. A new release produces a PR that
  bumps `version.txt`, the `PRUSA_CONNECT_VERSION` / `PRUSA_CONNECT_SHA256`
  pins in the Dockerfile, and the Kubernetes overlay — with a
  `Release-As: <version>` commit footer.
- **release-please** turns merged commits into a release PR; merging that
  tags the release, and the Build workflow publishes the images.
- **Container-only fixes** between upstream releases need a manual
  `Release-As:` footer appending a fourth prerelease component (for
  example `0.1.0-beta.1.1`) so the version can never collide with a future
  upstream release.

## Generated files ##

`.pre-commit-config.yaml` is generated — edit `.pre-commit-overlay.yaml`
and run `sh lint-config-update` instead. The Dockerfile's upstream checksum
pin is maintained by `sh update-upstream-pin`.

## Conventional commits ##

PR titles and commits follow
[Conventional Commits](https://www.conventionalcommits.org/); release notes
are assembled from them.
