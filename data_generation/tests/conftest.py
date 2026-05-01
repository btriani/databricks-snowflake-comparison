import pytest


@pytest.fixture
def fixed_seed() -> int:
    """Deterministic seed used across generator tests."""
    return 42
