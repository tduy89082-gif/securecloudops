from urllib.request import urlopen


def test_health_endpoint_returns_200():
    with urlopen(
        "http://127.0.0.1:8000/health",
        timeout=5,
    ) as response:
        assert response.status == 200