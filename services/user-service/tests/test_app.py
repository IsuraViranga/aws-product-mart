import pytest
import os

os.environ["DB_BACKEND"] = "memory"
os.environ["JWT_SECRET"] = "test-secret"

import sys
sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))
from app import app


@pytest.fixture
def client():
    app.config["TESTING"] = True
    with app.test_client() as client:
        yield client


def test_health(client):
    resp = client.get("/health")
    assert resp.status_code == 200
    assert resp.get_json()["status"] == "healthy"


def test_register(client):
    resp = client.post("/auth/register", json={
        "email": "test@example.com",
        "password": "password123",
        "name": "Test User"
    })
    assert resp.status_code == 201
    data = resp.get_json()
    assert "token" in data
    assert data["user"]["email"] == "test@example.com"


def test_login(client):
    resp = client.post("/auth/login", json={
        "email": "alice@cloudmart.example",
        "password": "password123"
    })
    assert resp.status_code == 200
    assert "token" in resp.get_json()


def test_login_wrong_password(client):
    resp = client.post("/auth/login", json={
        "email": "alice@cloudmart.example",
        "password": "wrongpassword"
    })
    assert resp.status_code == 401


def test_duplicate_email(client):
    client.post("/auth/register", json={
        "email": "dupe@example.com",
        "password": "password123",
        "name": "First User"
    })
    resp = client.post("/auth/register", json={
        "email": "dupe@example.com",
        "password": "password123",
        "name": "Second User"
    })
    assert resp.status_code == 409
