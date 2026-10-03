from fastapi.testclient import TestClient

from app.main import app

client = TestClient(app)


def test_task_validation() -> None:
    response = client.post("/tasks", json={"title": ""})
    assert response.status_code == 422
