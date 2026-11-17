# Deploying on Kubernetes #

Kubernetes is the first-class deployment target for this image. Upstream
maintains a complete, hardened set of manifests — ConfigMap, PVCs, Service,
and Deployment — and this repository ships a kustomize overlay that applies
them with the image published here.

## Quick start ##

```sh
kubectl create namespace prusa-connect
kubectl apply -k https://github.com/felddy/prusa-connect-container//deploy/kubernetes -n prusa-connect
```

Or clone this repository and edit `deploy/kubernetes/kustomization.yaml` to
pin the version you want before applying.

## What the manifests give you ##

The upstream base (pulled at the matching release tag) already encodes the
important operational decisions:

- **One replica, `Recreate` strategy.** The authorization graph is a single
  SQLite file with one writer, and the claims are `ReadWriteOnce`. Do not
  scale this Deployment.
- **Pod security:** `runAsNonRoot`, `runAsUser`/`runAsGroup`/`fsGroup`
  `10001`, `readOnlyRootFilesystem`, `allowPrivilegeEscalation: false`,
  all capabilities dropped, `RuntimeDefault` seccomp.
- **Probes:** startup and liveness read `/api/v1/health`; readiness reads
  `/api/v1/readiness`. All are `httpGet`, so they work with this shell-less
  image unchanged.
- **Configuration** is a single YAML file from a ConfigMap mounted at
  `/etc/prusa-connect/config.yaml`. The server reads no environment
  variables.
- **State** lives on two claims: `prusa-connect-state` (the resource overlay
  and authorization graph under `/config/config.d`) and
  `prusa-connect-storage` (uploaded files under `/storage`).

## Difference from upstream's manifests ##

The overlay removes the `upgrade-check` init container. Upstream's version
wraps `prusa_connect upgrade check` in `/bin/sh` so it can skip the check on
a first install; this image is distroless and carries no shell, and the bare
command exits non-zero when no database exists yet.

Before pointing an existing instance at a newer image, take the equivalent
precaution: snapshot (or back up) the two claims, or run
`prusa_connect upgrade check` against the state volume with a one-off pod
using the new image.

## Verifying the image ##

Every published image carries SLSA provenance and an SBOM attestation:

```sh
gh attestation verify oci://ghcr.io/felddy/prusa-connect:<tag> \
  --owner felddy --signer-repo felddy/reusable-workflows
```
