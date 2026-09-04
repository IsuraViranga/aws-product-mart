"""
product_service_test.py — full test suite for the product service.
Covers all endpoints: health, products CRUD, stock, categories.
"""

import pytest
import sys
import os

# Force memory backend for tests — no AWS credentials needed
os.environ["STORE_BACKEND"] = "memory"

sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))
from app import app


@pytest.fixture
def client():
    app.config["TESTING"] = True
    with app.test_client() as client:
        yield client


# ---------------------------------------------------------------------------
# Health & readiness
# ---------------------------------------------------------------------------

def test_health(client):
    resp = client.get("/health")
    assert resp.status_code == 200
    assert resp.get_json()["status"] == "healthy"


def test_ready(client):
    resp = client.get("/ready")
    assert resp.status_code == 200
    assert resp.get_json()["status"] == "ready"


# ---------------------------------------------------------------------------
# List, get, search, filter
# ---------------------------------------------------------------------------

def test_list_products(client):
    resp = client.get("/products")
    assert resp.status_code == 200
    data = resp.get_json()
    assert "products" in data
    assert data["count"] > 0


def test_get_product(client):
    resp = client.get("/products/prod-001")
    assert resp.status_code == 200
    assert resp.get_json()["id"] == "prod-001"


def test_get_product_not_found(client):
    resp = client.get("/products/does-not-exist")
    assert resp.status_code == 404


def test_search_products(client):
    resp = client.get("/products?search=headphone")
    assert resp.status_code == 200
    assert resp.get_json()["count"] >= 1


def test_filter_by_category(client):
    resp = client.get("/products?category=electronics")
    assert resp.status_code == 200
    for product in resp.get_json()["products"]:
        assert product["category"] == "electronics"


# ---------------------------------------------------------------------------
# Create
# ---------------------------------------------------------------------------

def test_create_product(client):
    resp = client.post("/products", json={
        "name": "Test Product",
        "price": 9.99,
        "category": "test"
    })
    assert resp.status_code == 201
    assert resp.get_json()["name"] == "Test Product"


def test_create_product_missing_fields(client):
    resp = client.post("/products", json={"description": "no name or price"})
    assert resp.status_code == 400
    assert resp.get_json()["error"] == "Bad Request"


# ---------------------------------------------------------------------------
# Update
# ---------------------------------------------------------------------------

def test_update_product(client):
    resp = client.put("/products/prod-001", json={"price": 99.99, "stock": 10})
    assert resp.status_code == 200
    data = resp.get_json()
    assert data["price"] == 99.99
    assert data["stock"] == 10
    assert "updatedAt" in data


def test_update_product_not_found(client):
    resp = client.put("/products/does-not-exist", json={"price": 1})
    assert resp.status_code == 404


def test_update_product_requires_body(client):
    resp = client.put("/products/prod-001", data="", content_type="application/json")
    assert resp.status_code == 400


# ---------------------------------------------------------------------------
# Delete
# ---------------------------------------------------------------------------

def test_delete_product(client):
    create_resp = client.post("/products", json={"name": "Temp Product", "price": 1.0})
    product_id = create_resp.get_json()["id"]

    assert client.delete(f"/products/{product_id}").status_code == 200
    assert client.get(f"/products/{product_id}").status_code == 404


def test_delete_product_not_found(client):
    resp = client.delete("/products/does-not-exist")
    assert resp.status_code == 404


# ---------------------------------------------------------------------------
# Stock
# ---------------------------------------------------------------------------

def test_check_stock(client):
    resp = client.get("/products/prod-001/stock")
    assert resp.status_code == 200
    data = resp.get_json()
    assert data["productId"] == "prod-001"
    assert data["available"] is True
    assert data["stock"] > 0


def test_check_stock_not_found(client):
    resp = client.get("/products/does-not-exist/stock")
    assert resp.status_code == 404


def test_decrement_stock(client):
    before = client.get("/products/prod-002/stock").get_json()["stock"]
    resp = client.post("/products/prod-002/stock/decrement", json={"quantity": 5})
    assert resp.status_code == 200
    assert resp.get_json()["productId"] == "prod-002"
    after = client.get("/products/prod-002/stock").get_json()["stock"]
    assert after == before - 5


def test_decrement_stock_insufficient(client):
    resp = client.post("/products/prod-002/stock/decrement", json={"quantity": 1000000})
    assert resp.status_code == 409
    assert resp.get_json()["error"] == "Conflict"


def test_decrement_stock_not_found(client):
    # Note: the store's decrement_stock() returns False for both "product not
    # found" and "insufficient stock", so a missing product currently surfaces
    # as 409 Conflict rather than 404 Not Found. This test documents that
    # actual behaviour rather than the ideal one.
    resp = client.post("/products/does-not-exist/stock/decrement", json={"quantity": 1})
    assert resp.status_code == 409
    assert resp.get_json()["error"] == "Conflict"


# ---------------------------------------------------------------------------
# Categories
# ---------------------------------------------------------------------------

def test_list_categories(client):
    resp = client.get("/categories")
    assert resp.status_code == 200
    data = resp.get_json()
    assert "categories" in data
    assert "electronics" in data["categories"]
    assert data["categories"] == sorted(data["categories"])
