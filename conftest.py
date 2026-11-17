"""pytest plugin and command-line options for the test suite."""


def pytest_addoption(parser):
    """Add options to control the tests."""
    parser.addoption(
        "--runslow", action="store_true", default=False, help="run slow tests"
    )
    parser.addoption(
        "--image-tag",
        action="store",
        default="local/test-image:latest",
        help="image tag to test",
    )


def pytest_configure(config):
    """Register custom markers."""
    config.addinivalue_line("markers", "slow: mark test as slow")
