"""Verify the container image starts, serves, and stays unprivileged."""

# Standard Python Libraries
from io import BytesIO
import os
import tarfile
import time

# Third-Party Libraries
import pytest
import requests

HEALTH_TIMEOUT_SECONDS = 120
RELEASE_TAG = os.environ.get("RELEASE_TAG")
VERSION_LABEL = "org.opencontainers.image.version"


def test_container_running(main_container):
    """Verify the container starts under the hardened runtime options."""
    main_container.reload()
    assert main_container.status in ("created", "running")


@pytest.mark.slow
def test_wait_for_healthy(main_container):
    """Wait for the Docker healthcheck to report healthy."""
    deadline = time.time() + HEALTH_TIMEOUT_SECONDS
    status = "unknown"
    while time.time() < deadline:
        main_container.reload()
        status = main_container.attrs["State"]["Health"]["Status"]
        if status == "healthy":
            break
        assert status != "unhealthy", "healthcheck reported unhealthy"
        time.sleep(2)
    assert status == "healthy", f"not healthy after {HEALTH_TIMEOUT_SECONDS}s"


def test_health_endpoint_reports_upstream_version(main_container_port, project_version):
    """Verify /api/v1/health answers ok with the pinned upstream version."""
    response = requests.get(
        f"http://127.0.0.1:{main_container_port}/api/v1/health", timeout=10
    )
    response.raise_for_status()
    health = response.json()
    assert health["status"] == "ok"
    assert health["version"] == project_version


def test_frontend_served(main_container_port):
    """Verify the embedded web application is served at /."""
    response = requests.get(f"http://127.0.0.1:{main_container_port}/", timeout=10)
    response.raise_for_status()
    assert response.headers["content-type"].startswith("text/html")


def test_runs_unprivileged(main_container):
    """Verify the server process runs as the fixed non-root uid."""
    assert main_container.attrs["Config"]["User"] == "prusa"
    processes = main_container.top(ps_args="-o pid,uid,comm")
    uids = {row[1] for row in processes["Processes"]}
    assert uids == {"10001"}


def test_extension_releases_present(main_container):
    """Verify the first-party extension releases shipped in the image."""
    expected = {
        "buddy-debug-logs",
        "fleet-stats",
        "fractal",
        "materials",
        "parts",
        "server-slicing",
        "threemf",
    }
    # distroless has no shell to exec `ls`; read the directory through the
    # archive API instead.
    stream, _ = main_container.get_archive("/opt/modules")
    archive = BytesIO(b"".join(stream))
    with tarfile.open(fileobj=archive) as tar:
        names = {
            member.name.split("/")[1]
            for member in tar.getmembers()
            if "/" in member.name
        }
    assert expected <= names


def test_version_output(version_container, project_version):
    """Verify the binary reports the pinned upstream version."""
    assert version_container.wait()["StatusCode"] == 0
    assert project_version in version_container.logs().decode("utf-8")


@pytest.mark.skipif(
    RELEASE_TAG is None, reason="this is not a release (RELEASE_TAG not set)"
)
def test_release_version(project_version):
    """Verify the release tag matches the project version."""
    assert (
        RELEASE_TAG == f"v{project_version}"
    ), "RELEASE_TAG does not match the project version"


@pytest.mark.skipif(
    RELEASE_TAG is None, reason="this is not a release (RELEASE_TAG not set)"
)
def test_version_label(main_container, project_version):
    """Verify the image version label matches the project version on releases."""
    labels = main_container.image.labels
    assert labels.get(VERSION_LABEL) == project_version
