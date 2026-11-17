# Deploying with Podman #

Podman runs this image well, rootless included: the server is a single
static binary listening on an unprivileged port, running as uid 10001 with
no capabilities.

## Quadlet (systemd-managed, recommended) ##

Drop this unit at `~/.config/containers/systemd/prusa-connect.container`
(rootless) or `/etc/containers/systemd/prusa-connect.container` (system):

```ini
[Unit]
Description=Prusa Connect server

[Container]
Image=ghcr.io/felddy/prusa-connect:prerelease
AutoUpdate=registry
PublishPort=8080:8080
ReadOnly=true
DropCapability=all
NoNewPrivileges=true

# The server's write targets. Named volumes are seeded from the image with
# the right ownership on first use.
Volume=prusa-connect-config:/config/config.d
Volume=prusa-connect-data:/data
Volume=prusa-connect-files:/files
Volume=prusa-connect-storage:/storage
Volume=prusa-connect-tmp:/tmp

# Optional: your own configuration file (the server reads no environment
# variables; one YAML file configures everything).
# Volume=%h/prusa-connect/config.yaml:/config/config.yaml:ro,Z

[Service]
Restart=on-failure

[Install]
WantedBy=default.target
```

Then:

```sh
systemctl --user daemon-reload
systemctl --user start prusa-connect
```

## Plain podman run ##

```sh
podman run -d --name prusa-connect \
  --read-only --cap-drop all --security-opt no-new-privileges \
  -p 8080:8080 \
  -v prusa-connect-config:/config/config.d \
  -v prusa-connect-data:/data \
  -v prusa-connect-files:/files \
  -v prusa-connect-storage:/storage \
  -v prusa-connect-tmp:/tmp \
  ghcr.io/felddy/prusa-connect:prerelease
```

## Notes ##

- **Bind mounts:** a named volume is seeded with uid 10001 ownership from
  the image; a bind-mounted host directory is not. Chown bind mounts to
  `10001:10001` (rootless: `podman unshare chown 10001:10001 <dir>`).
- **Printer listeners below port 1024:** the image deliberately carries no
  file capabilities. Podman containers get
  `net.ipv4.ip_unprivileged_port_start=0` in their network namespace, so a
  connector listener on :80 binds without any added capability. If your
  runtime keeps the traditional boundary, move the listener above 1024 in
  `config.yaml` or grant `NET_BIND_SERVICE` at the container level.
- **Health:** the image's healthcheck probes the binary itself
  (`prusa_connect core healthcheck`); `podman healthcheck run
  prusa-connect` exercises it manually.
