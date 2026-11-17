# Deploying with Docker Compose #

If Compose is what you run, the repository root carries a hardened
[`compose.yaml`](../../compose.yaml) mirroring upstream's service
definition: read-only root filesystem, all capabilities dropped,
`no-new-privileges`, named volumes over every write target, and bounded
log files.

```sh
docker compose up -d
```

Then open `http://<host>:8080/`.

## Configuration ##

The server reads no environment variables. To configure it, place a
`config.yaml` beside the compose file and uncomment the config mount in
`compose.yaml`. Started without one, the server uses its defaults: SQLite
persistence and the API on `:8080`.

## Volumes ##

| Mount               | Contents                                              |
| ------------------- | ----------------------------------------------------- |
| `/config/config.d`  | Resource overlay and authorization graph (SQLite)     |
| `/data`             | Installed extensions and their data                   |
| `/files`            | File storage                                          |
| `/storage`          | Uploaded content (G-code)                             |
| `/tmp`              | Scratch space (root filesystem is read-only)          |

Named volumes are seeded from the image owned by uid 10001. If you switch
to bind mounts, `chown -R 10001:10001` each host directory first.
