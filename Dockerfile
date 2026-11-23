# syntax=docker/dockerfile:1

# The upstream release this image packages: the version and the sha256 of its
# source archive, which GitHub reports as the asset's digest. The two move
# together — Renovate rewrites both when upstream publishes a release — and
# `ADD --checksum` below fails the build if the archive and the pin disagree.
ARG PRUSA_CONNECT_VERSION=0.1.0-beta.1
ARG PRUSA_CONNECT_SHA256=96990b788111fae5d547c0a43d962ea67eb4585a74b8bb478a2aa514021415cf

# Every stage before the runtime runs on the build platform and cross-compiles
# for the target, so a wide platform matrix never executes under emulation:
# the pnpm output is architecture-independent and Go cross-compiles with
# CGO disabled. Only the final stage is assembled per target platform, and it
# runs nothing.

# ---------------------------------------------------------------------------
# The sanctioned build input: the release's own source archive, not a git
# checkout. Upstream's container doc is explicit that images build from
# `prusa-connect-<version>-source.tar.gz`.
FROM --platform=$BUILDPLATFORM alpine:3.24@sha256:f59abe656b692d901e184be3445e084786602108599d2a51d229c0f5a48c71bf AS src
ARG PRUSA_CONNECT_VERSION
ARG PRUSA_CONNECT_SHA256
ADD --checksum=sha256:${PRUSA_CONNECT_SHA256} \
    https://github.com/prusa3d/prusa-connect/releases/download/v${PRUSA_CONNECT_VERSION}/prusa-connect-${PRUSA_CONNECT_VERSION}-source.tar.gz \
    /prusa-connect-source.tar.gz
RUN mkdir /src && tar -xzf /prusa-connect-source.tar.gz -C /src --strip-components=1

# ---------------------------------------------------------------------------
# The component library and the client SDK, built once for the two stages
# below. Stage layout and ordering follow upstream's docker/server/Dockerfile;
# the node and golang digests are upstream's own pins, so this build uses the
# toolchains the release was tested with.
FROM --platform=$BUILDPLATFORM node:24-alpine@sha256:116b800c3754b440ee0aa3ed2f20f5bf3d99a554bfd9adeea09ea8017f6e85f5 AS packages-builder
ENV PNPM_HOME=/pnpm
ENV PATH="$PNPM_HOME:$PATH"
ENV HUSKY=0
ENV CI=true
RUN corepack enable
WORKDIR /app
COPY --from=src /src/packages/standards ./packages/standards
COPY --from=src /src/packages/typescript ./packages/typescript
RUN cd packages/typescript && pnpm install --frozen-lockfile && pnpm run build
COPY --from=src /src/packages/svelte ./packages/svelte
COPY --from=src /src/docs/errors/error-codes.json ./docs/errors/error-codes.json
# --ignore-scripts: the package's `prepare` hook writes its i18n catalogues
# from sources, and `pnpm run build` writes them anyway.
RUN cd packages/svelte && pnpm install --frozen-lockfile --ignore-scripts && pnpm run build

# The core's own web application, which the Go binary embeds and serves at /.
FROM packages-builder AS app-builder
COPY --from=src /src/packages/fractal/client ./packages/fractal/client
RUN cd packages/fractal/client && pnpm install --frozen-lockfile && pnpm run build
COPY --from=src /src/frontend ./frontend
RUN cd frontend && pnpm install --frozen-lockfile && pnpm run build && test -f dist/index.html

# The browser halves of the extensions the image carries in /opt/modules.
FROM packages-builder AS extensions-builder
COPY --from=src /src/extensions/fleet-stats ./extensions/fleet-stats
RUN cd extensions/fleet-stats/ui && pnpm install --frozen-lockfile && pnpm run build && test -f dist/ui/index.js
COPY --from=src /src/extensions/parts ./extensions/parts
RUN cd extensions/parts/client && pnpm install --frozen-lockfile && pnpm run build && \
    cd ../ui && pnpm install --frozen-lockfile && pnpm run build && test -f dist/ui/index.js
COPY --from=src /src/extensions/buddy-debug-logs ./extensions/buddy-debug-logs
RUN cd extensions/buddy-debug-logs/client && pnpm install --frozen-lockfile && pnpm run build && \
    cd ../ui && pnpm install --frozen-lockfile && pnpm run build && test -f dist/ui/index.js
COPY --from=src /src/extensions/threemf ./extensions/threemf
RUN cd extensions/threemf/client && pnpm install --frozen-lockfile && pnpm run build && \
    cd ../ui && pnpm install --frozen-lockfile && pnpm run build && test -f dist/ui/index.js
COPY --from=src /src/extensions/server-slicing ./extensions/server-slicing
RUN cd extensions/server-slicing/client && pnpm install --frozen-lockfile && pnpm run build && \
    cd ../ui && pnpm install --frozen-lockfile && pnpm run build && test -f dist/ui/index.js
COPY --from=src /src/extensions/materials ./extensions/materials
RUN cd extensions/materials/client && pnpm install --frozen-lockfile && pnpm run build && \
    cd ../ui && pnpm install --frozen-lockfile && pnpm run build && test -f dist/ui/index.js

# ---------------------------------------------------------------------------
# The Go server and the extension binaries, cross-compiled for the target
# platform. Host tools (detect-build-tags, compress-app) run natively; only
# `go build` sees GOOS/GOARCH.
FROM --platform=$BUILDPLATFORM golang:1.26.11-trixie@sha256:fa340cb59ebeb1d53ac1cccfc334201d938fe5f3458003cccb767096d8e032b8 AS builder

WORKDIR /app

# The nested sdk module is resolved through a local replace in go.mod, so its
# manifest has to exist before any module-graph command runs. It has no go.sum:
# the sdk imports nothing outside the standard library.
COPY --from=src /src/go.* ./
COPY --from=src /src/sdk/go.mod ./sdk/

# Warm the module cache. Every module this build needs is public, so the step
# takes no credential and no BuildKit secret.
RUN go mod download

COPY --from=src /src/ ./

# The web application, into the directory //go:embed reads. It lands after the
# source copy, which brings the placeholder-only directory, and before
# `go build`, which embeds it.
COPY --from=app-builder /app/frontend/dist ./internal/transport/http/httpapi/appdist

# Each text file of the app is replaced with a gzip copy, which the server
# sends to a browser as it is stored.
RUN go run ./cmd/compress-app ./internal/transport/http/httpapi/appdist

# CONFIG_FILE and EXTRA_BUILD_TAGS are upstream's Makefile knobs under the
# Makefile's own names and defaults, so this build builds what upstream's
# `make build-config` builds.
#
# UPGRADE_PUBLIC_KEYS stays empty: it bakes in the keys the binary's
# self-upgrade mechanism trusts, and in-place self-upgrade has no business
# inside a read-only container — new versions arrive as new image tags.
#
# The binary reports PRUSA_CONNECT_VERSION in its log, at /api/v1/health and
# for --version, the same stamp upstream's release builds carry.
#
# CONTAINER_VERSION is CI's claim of what this image is (from version.txt).
# It must agree with the upstream pin above; the guard catches the two files
# drifting apart. Local builds may leave it unset.
ARG CONFIG_FILE=config/config.yaml
ARG EXTRA_BUILD_TAGS=""
ARG UPGRADE_PUBLIC_KEYS=""
ARG DOCS_URL=https://beta.prusa3d.com/connect-local/docs/{version}/
ARG PRUSA_CONNECT_VERSION
ARG CONTAINER_VERSION=""
ARG TARGETOS
ARG TARGETARCH
ARG TARGETVARIANT
RUN test -z "$CONTAINER_VERSION" || test "$CONTAINER_VERSION" = "$PRUSA_CONNECT_VERSION" || \
    { echo "CONTAINER_VERSION=$CONTAINER_VERSION does not match PRUSA_CONNECT_VERSION=$PRUSA_CONNECT_VERSION: version.txt and the Dockerfile pin have drifted" >&2; exit 1; }
RUN TAGS="$(go run ./cmd/detect-build-tags --config "$CONFIG_FILE" --variant full --extra "$EXTRA_BUILD_TAGS")" && \
    echo "Building with tags: full $TAGS" && \
    export CGO_ENABLED=0 GOOS="$TARGETOS" GOARCH="$TARGETARCH" GOARM="${TARGETVARIANT#v}" && \
    go build -v -tags "full $TAGS" \
    -ldflags="-X github.com/prusa3d/prusa-connect/internal/kernel/version.stamped=${PRUSA_CONNECT_VERSION} -X github.com/prusa3d/prusa-connect/internal/kernel/version.docsURL=${DOCS_URL} -X github.com/prusa3d/prusa-connect/internal/upgrade.officialPublicKeys=${UPGRADE_PUBLIC_KEYS}" \
    -o /prusa_connect ./cmd/prusa-connect

# The extension UI bundles, built in the node stage, where the packed
# releases expect them. The source copy above brought only their sources.
COPY --from=extensions-builder /app/extensions/parts/ui/dist ./extensions/parts/ui/dist
COPY --from=extensions-builder /app/extensions/buddy-debug-logs/ui/dist ./extensions/buddy-debug-logs/ui/dist
COPY --from=extensions-builder /app/extensions/threemf/ui/dist ./extensions/threemf/ui/dist
COPY --from=extensions-builder /app/extensions/server-slicing/ui/dist ./extensions/server-slicing/ui/dist
COPY --from=extensions-builder /app/extensions/materials/ui/dist ./extensions/materials/ui/dist

# Each extension, laid out as the release `module add` reads, by upstream's
# own pack script. The binary name must be <name>_<GOOS>_<GOARCH>: that is the
# file the host looks for, so it names the target platform, not the builder's.
RUN export CGO_ENABLED=0 GOOS="$TARGETOS" GOARCH="$TARGETARCH" GOARM="${TARGETVARIANT#v}" && \
    BINARY="/tmp/parts_$(go env GOOS)_$(go env GOARCH)" && \
    go -C extensions/parts build -o "$BINARY" . && \
    sh extensions/scripts/pack-release.sh extensions/parts/ui/dist "$BINARY" /opt/modules/parts
RUN export CGO_ENABLED=0 GOOS="$TARGETOS" GOARCH="$TARGETARCH" GOARM="${TARGETVARIANT#v}" && \
    BINARY="/tmp/buddy-debug-logs_$(go env GOOS)_$(go env GOARCH)" && \
    go -C extensions/buddy-debug-logs build -o "$BINARY" . && \
    sh extensions/scripts/pack-release.sh extensions/buddy-debug-logs/ui/dist "$BINARY" /opt/modules/buddy-debug-logs
RUN export CGO_ENABLED=0 GOOS="$TARGETOS" GOARCH="$TARGETARCH" GOARM="${TARGETVARIANT#v}" && \
    BINARY="/tmp/threemf_$(go env GOOS)_$(go env GOARCH)" && \
    go -C extensions/threemf build -o "$BINARY" . && \
    sh extensions/scripts/pack-release.sh extensions/threemf/ui/dist "$BINARY" /opt/modules/threemf
RUN export CGO_ENABLED=0 GOOS="$TARGETOS" GOARCH="$TARGETARCH" GOARM="${TARGETVARIANT#v}" && \
    BINARY="/tmp/server-slicing_$(go env GOOS)_$(go env GOARCH)" && \
    go -C extensions/server-slicing build -o "$BINARY" . && \
    sh extensions/scripts/pack-release.sh extensions/server-slicing/ui/dist "$BINARY" /opt/modules/server-slicing
RUN export CGO_ENABLED=0 GOOS="$TARGETOS" GOARCH="$TARGETARCH" GOARM="${TARGETVARIANT#v}" && \
    BINARY="/tmp/materials_$(go env GOOS)_$(go env GOARCH)" && \
    go -C extensions/materials build -o "$BINARY" . && \
    sh extensions/scripts/pack-release.sh extensions/materials/ui/dist "$BINARY" /opt/modules/materials

# The Fractal release has no web page: its bundle is the manifest and the
# route document alone. Its NATS dependencies are not the core's, so this
# build downloads them.
RUN export CGO_ENABLED=0 GOOS="$TARGETOS" GOARCH="$TARGETARCH" GOARM="${TARGETVARIANT#v}" && \
    BINARY="/tmp/fractal_$(go env GOOS)_$(go env GOARCH)" && \
    go -C packages/fractal build -o "$BINARY" . && \
    mkdir /tmp/fractal-bundle && \
    cp packages/fractal/module.yaml packages/fractal/openapi.json /tmp/fractal-bundle/ && \
    sh extensions/scripts/pack-release.sh /tmp/fractal-bundle "$BINARY" /opt/modules/fractal

# ---------------------------------------------------------------------------
# Runtime filesystem pieces distroless cannot create itself (no shell, no
# RUN): the prusa account appended to distroless's own passwd/group, and the
# directories the server writes into. Fixed uid/gid 10001, upstream's choice,
# so bind mounts chowned for upstream's image work here unchanged.
FROM gcr.io/distroless/static-debian13:nonroot@sha256:8ce6dd87e9823c5b48dcfb2c8604714ccb351ce59607327bcc4957448da279b5 AS distroless

FROM --platform=$BUILDPLATFORM alpine:3.24@sha256:f59abe656b692d901e184be3445e084786602108599d2a51d229c0f5a48c71bf AS rootfs
RUN mkdir -p /staging/etc
COPY --from=distroless /etc/passwd /etc/group /staging/etc/
RUN printf 'prusa:x:10001:10001:prusa:/:/sbin/nologin\n' >> /staging/etc/passwd && \
    printf 'prusa:x:10001:\n' >> /staging/etc/group && \
    install -d -o 10001 -g 10001 -m 0750 /staging/data /staging/files /staging/storage /staging/config/config.d

# ---------------------------------------------------------------------------
# The runtime image: a static binary, its extension releases, and nothing
# else. distroless/static ships the CA bundle at the path Go's crypto/x509
# reads, tzdata, and a world-writable /tmp; there is no shell, package
# manager, or libc to patch or exploit.
FROM distroless

ARG PRUSA_CONNECT_VERSION
LABEL com.prusa3d.connect.version=${PRUSA_CONNECT_VERSION}
LABEL org.opencontainers.image.authors="markf+github@geekpad.com"
LABEL org.opencontainers.image.vendor="Geekpad"

COPY --from=builder /prusa_connect /prusa_connect

# First-party extensions as releases, one directory each. They do nothing
# until the operator's `core.modules_local` names them. Owned by root,
# readable by the runtime user, because nothing writes here.
COPY --from=builder /opt/modules /opt/modules
COPY --from=extensions-builder /app/extensions/fleet-stats/ui/dist /opt/modules/fleet-stats

COPY --from=rootfs /staging/etc/passwd /etc/passwd
COPY --from=rootfs /staging/etc/group /etc/group

# Runtime write targets, owned by the runtime user before any volume is
# mounted, so a named volume seeded from the image lands writable with no
# entrypoint chown. A bind mount keeps the host directory's ownership and has
# to be chowned to 10001:10001 by whoever mounts it.
#
# /config/config.d holds what the server writes beside the operator's
# read-only config.yaml: the machine-owned resource overlay and the
# authorization graph. Without it the core refuses to start under a read-only
# root filesystem.
COPY --from=rootfs --chown=10001:10001 --chmod=0750 /staging/data /data
COPY --from=rootfs --chown=10001:10001 --chmod=0750 /staging/files /files
COPY --from=rootfs --chown=10001:10001 --chmod=0750 /staging/storage /storage
COPY --from=rootfs --chown=10001:10001 --chmod=0750 /staging/config/config.d /config/config.d

# Relative paths in config/config.yaml (./data, ./files, ./storage) and the
# default --config path resolve from here.
WORKDIR /

USER prusa

# Probes GET /api/v1/readiness through the binary itself, so the image needs
# no curl or wget. start-period covers the cold path: opening the
# authorization graph and starting every declared resource.
HEALTHCHECK --interval=30s --timeout=5s --start-period=30s --retries=3 \
    CMD ["/prusa_connect", "core", "healthcheck"]

# CMD rather than a longer ENTRYPOINT, so `docker run <image> core
# healthcheck` and any other subcommand still reach the binary.
ENTRYPOINT ["/prusa_connect"]
CMD ["core"]
