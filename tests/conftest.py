"""pytest configuration and container fixtures."""

# Standard Python Libraries
import os

# Third-Party Libraries
import docker
import pytest

MAIN_SERVICE_NAME = "prusa-connect"
VERSION_FILE = "version.txt"
VERSION_SERVICE_NAME = f"{MAIN_SERVICE_NAME}-version"


def _docker_client():
    """Lazy Docker client — only connects when actually needed."""
    return docker.from_env()


@pytest.fixture(autouse=True)
def group_github_log_lines(request):
    """Group log lines when running in GitHub actions."""
    if os.environ.get("GITHUB_ACTIONS") != "true":
        # Not running in GitHub actions
        yield
        return
    # Group using the current test name
    print()
    print(f"::group::{request.node.name}")
    yield
    print()
    print("::endgroup::")


@pytest.fixture(scope="session")
def main_container(image_tag):
    """Run the server the way the deployment docs tell operators to.

    Read-only root filesystem, every capability dropped, no privilege
    escalation, and anonymous volumes over the directories the image marks
    as its write targets. The server needs no environment variables and no
    config file to start with defaults on :8080.
    """
    container = _docker_client().containers.run(
        image_tag,
        cap_drop=["ALL"],
        detach=True,
        name=MAIN_SERVICE_NAME,
        ports={"8080/tcp": None},
        read_only=True,
        security_opt=["no-new-privileges:true"],
        volumes=[
            "/config/config.d",
            "/data",
            "/files",
            "/storage",
            # a container mount target, not a host temp path
            "/tmp",  # nosec B108
        ],
    )
    yield container
    container.remove(force=True)


@pytest.fixture(scope="session")
def main_container_port(main_container):
    """Return the host port mapped to the server's API port."""
    main_container.reload()
    return main_container.attrs["NetworkSettings"]["Ports"]["8080/tcp"][0]["HostPort"]


@pytest.fixture(scope="session")
def version_container(image_tag):
    """Run the image with the binary's --version flag."""
    container = _docker_client().containers.run(
        image_tag,
        command=["--version"],
        detach=True,
        name=VERSION_SERVICE_NAME,
    )
    yield container
    container.remove(force=True)


@pytest.fixture(scope="session")
def project_version():
    """Get the project version."""
    with open(VERSION_FILE) as f:
        version = f.read().strip()
    return version


@pytest.fixture(scope="session")
def image_tag(request):
    """Get the image tag to test."""
    return request.config.getoption("--image-tag")


def pytest_collection_modifyitems(config, items):
    """Modify collected tests based on custom marks and commandline options."""
    if config.getoption("--runslow"):
        # --runslow given in cli: do not skip slow tests
        return
    skip_slow = pytest.mark.skip(reason="need --runslow option to run")
    for item in items:
        if "slow" in item.keywords:
            item.add_marker(skip_slow)
