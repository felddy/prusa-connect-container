# Prusa Connect Container #

[![Build](https://github.com/felddy/prusa-connect-container/actions/workflows/build.yml/badge.svg)](https://github.com/felddy/prusa-connect-container/actions/workflows/build.yml)
[![CodeQL](https://github.com/felddy/prusa-connect-container/actions/workflows/codeql-analysis.yml/badge.svg)](https://github.com/felddy/prusa-connect-container/actions/workflows/codeql-analysis.yml)
![Platforms](https://img.shields.io/badge/platforms-amd64%20%7C%20arm64%20%7C%20ppc64le%20%7C%20riscv64%20%7C%20s390x-blue)

Automated, attested, multi-architecture container builds of
[Prusa Connect](https://github.com/prusa3d/prusa-connect) — the self-hosted
local server for Prusa printers.

Upstream documents building the container yourself from each release's
source archive and plans official images for a future public release. Until
those exist, this project fills the gap: every upstream release is built
unmodified from its sanctioned, checksum-verified source archive and
published to GitHub Container Registry with SBOMs, SLSA provenance, and
daily CVE rescans.

```text
ghcr.io/felddy/prusa-connect
```

## Tags ##

| Tag          | Meaning                                                    |
| ------------ | ---------------------------------------------------------- |
| `x.y.z…`     | A specific upstream release (immutable)                    |
| `prerelease` | The newest prerelease build                                |
| `latest`     | The newest stable release (none yet — upstream is in beta) |
| `edge`       | Weekly rebuild of the development branch state             |
| `develop`    | Latest build from this repository's default branch         |

## How this image differs from building upstream's ##

The build follows upstream's own `docker/server/Dockerfile` stage for stage
— same toolchain pins, same build tags, same extension packaging — with
three deliberate changes:

- **Distroless runtime.** The final stage is
  `gcr.io/distroless/static-debian13` instead of `debian:trixie-slim`: no
  shell, no package manager, no libc. The attack surface is the static
  binary and its extension bundles; CVE scans have almost nothing to flag.
- **Cross-compiled multi-arch.** All heavy stages run on the build platform
  and cross-compile, so images ship for five architectures without
  emulation: `amd64`, `arm64`, `ppc64le`, `riscv64`, `s390x`.
  (`arm/v7` is excluded: upstream's parts extension does not compile for
  32-bit targets.)
- **Verified source.** The release source archive is fetched by checksum
  (`ADD --checksum`), pinned in the Dockerfile and updated in lockstep with
  the version by automation.

Unchanged from upstream: fixed uid/gid `10001`, no file capabilities, the
binary-as-healthcheck probe, and a filesystem layout that runs under a
read-only root with all capabilities dropped.

## Deployment ##

In order of preference:

1. **[Kubernetes](docs/deployment/kubernetes.md)** — a kustomize overlay in
   `deploy/kubernetes/` applies upstream's own hardened manifests with this
   image.
1. **[Podman](docs/deployment/podman.md)** — a Quadlet unit for
   systemd-managed (rootless) operation.
1. **[Docker Compose](docs/deployment/docker-compose.md)** — a hardened
   `compose.yaml` at the repository root.

Quick trial run:

```sh
docker run -d --name prusa-connect \
  --read-only --cap-drop ALL --security-opt no-new-privileges \
  -p 8080:8080 \
  -v prusa-connect-config:/config/config.d \
  -v prusa-connect-data:/data \
  -v prusa-connect-files:/files \
  -v prusa-connect-storage:/storage \
  -v prusa-connect-tmp:/tmp \
  ghcr.io/felddy/prusa-connect:prerelease
```

Then open `http://localhost:8080/`.

## Configuration ##

The server reads **no environment variables**: one YAML file configures
everything, mounted read-only at `/config/config.yaml` (or passed with
`-config`). Started without one, it uses defaults: SQLite persistence and
the API on `:8080`. Secrets are file paths in that config, never values.
See [upstream's documentation](https://github.com/prusa3d/prusa-connect)
for the configuration reference.

Write targets (back these with volumes):

| Path               | Contents                                          |
| ------------------ | ------------------------------------------------- |
| `/config/config.d` | Resource overlay and authorization graph (SQLite) |
| `/data`            | Installed extensions and their data               |
| `/files`           | File storage                                      |
| `/storage`         | Uploaded content (G-code)                         |
| `/tmp`             | Scratch space (root filesystem is read-only)      |

Run a single replica: the authorization graph is one SQLite file with one
writer.

## Verifying images ##

Every push is signed and attested. Verify provenance with the GitHub CLI:

```sh
gh attestation verify oci://ghcr.io/felddy/prusa-connect:prerelease \
  --owner felddy --signer-repo felddy/reusable-workflows
```

## Licensing ##

Two licenses apply, and the distinction matters:

- **This repository** (Dockerfile, workflows, tests, documentation) is MIT.
- **The published images contain Prusa Connect**, which Prusa Research
  licenses under the **Open Community License v1.1 with the Micro v1,
  NoSaaS v1, and SWAtt v1 add-ons** — not an OSI open-source license. In
  practice, for users of these images:
  - Use and redistribution must be **non-commercial**, under the same
    license, with attribution preserved.
  - Businesses (including affiliates) over **EUR 1M annual gross revenue**
    may not use it without a business license from Prusa Research.
  - Offering its functionality to third parties as a hosted/managed
    service (**SaaS**) is not permitted.

  Read [upstream's LICENSE](https://github.com/prusa3d/prusa-connect/blob/main/LICENSE)
  before deploying; your use must satisfy it. These images are published
  free of charge as a community service.

## Relationship to upstream ##

Unofficial and unaffiliated. Images are built from unmodified upstream
release sources; nothing is patched. Upstream plans official images "for
the public release" — when those arrive, this project will likely point
there and wind down. Improvements made here (cross-compiled multi-arch
builds, the distroless runtime) are candidates for contribution upstream.

Found a bug in Prusa Connect itself? Report it
[upstream](https://github.com/prusa3d/prusa-connect/issues). Found a
problem with the container build or packaging? That belongs in
[this repository's issues](https://github.com/felddy/prusa-connect-container/issues).
