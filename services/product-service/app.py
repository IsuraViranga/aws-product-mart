"""
CloudMart Product Service
Manages product catalogue: CRUD operations, search, category filtering.

Data Store:
  - Default: In-memory dictionary (for local dev / Docker Compose)
  - Cloud:   Set STORE_BACKEND=dynamodb|firestore|cosmosdb via env var
             to use a managed NoSQL database (requires workload identity / credentials)
"""

import os
import uuid
import logging
from datetime import datetime
from decimal import Decimal
from flask import Flask, jsonify, request, abort

# ---------------------------------------------------------------------------
# App setup
# ---------------------------------------------------------------------------
app = Flask(__name__)
app.config["JSON_SORT_KEYS"] = False

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(levelname)s] %(name)s: %(message)s",
)
logger = logging.getLogger("product-service")

# ---------------------------------------------------------------------------
# Data store abstraction
# ---------------------------------------------------------------------------

# Seed data
SEED_PRODUCTS = [
    {
        "id": "prod-001",
        "name": "Wireless Bluetooth Headphones",
        "description": "Premium noise-cancelling over-ear headphones with 30-hour battery life",
        "price": 79.99,
        "category": "electronics",
        "stock": 150,
        "imageUrl": "/images/headphones.jpg",
        "createdAt": "2025-01-15T10:00:00Z",
    },
    {
        "id": "prod-002",
        "name": "Organic Ceylon Tea (100 bags)",
        "description": "Premium hand-picked Ceylon black tea from Nuwara Eliya estates",
        "price": 12.99,
        "category": "food",
        "stock": 500,
        "imageUrl": "/images/ceylon-tea.jpg",
        "createdAt": "2025-01-15T10:00:00Z",
    },
    {
        "id": "prod-003",
        "name": "USB-C Laptop Stand",
        "description": "Adjustable aluminium stand with integrated USB-C hub (HDMI, USB 3.0, PD charging)",
        "price": 49.99,
        "category": "electronics",
        "stock": 75,
        "imageUrl": "/images/laptop-stand.jpg",
        "createdAt": "2025-01-15T10:00:00Z",
    },
    {
        "id": "prod-004",
        "name": "Handloom Cotton Sarong",
        "description": "Traditional Sri Lankan handloom sarong, 100% cotton, machine washable",
        "price": 24.99,
        "category": "clothing",
        "stock": 200,
        "imageUrl": "/images/sarong.jpg",
        "createdAt": "2025-01-15T10:00:00Z",
    },
    {
        "id": "prod-005",
        "name": "Mechanical Keyboard (TKL)",
        "description": "Tenkeyless mechanical keyboard with Cherry MX Brown switches, RGB backlight",
        "price": 89.99,
        "category": "electronics",
        "stock": 60,
        "imageUrl": "/images/keyboard.jpg",
        "createdAt": "2025-01-15T10:00:00Z",
    },
    {
        "id": "prod-006",
        "name": "Coconut Oil (Cold Pressed, 500ml)",
        "description": "Virgin cold-pressed coconut oil from Southern Province, Sri Lanka",
        "price": 8.99,
        "category": "food",
        "stock": 300,
        "imageUrl": "/images/coconut-oil.jpg",
        "createdAt": "2025-01-15T10:00:00Z",
    },
]


class InMemoryStore:
    """Simple in-memory product store for local development."""

    def __init__(self):
        self.products = {p["id"]: dict(p) for p in SEED_PRODUCTS}

    def get_all(self, category=None, search=None):
        results = list(self.products.values())
        if category:
            results = [p for p in results if p["category"] == category]
        if search:
            q = search.lower()
            results = [
                p
                for p in results
                if q in p["name"].lower() or q in p["description"].lower()
            ]
        return results

    def get_by_id(self, product_id):
        return self.products.get(product_id)

    def create(self, data):
        product_id = f"prod-{uuid.uuid4().hex[:6]}"
        product = {
            "id": product_id,
            "name": data["name"],
            "description": data.get("description", ""),
            "price": float(data["price"]),
            "category": data.get("category", "general"),
            "stock": int(data.get("stock", 0)),
            "imageUrl": data.get("imageUrl", ""),
            "createdAt": datetime.utcnow().isoformat() + "Z",
        }
        self.products[product_id] = product
        return product

    def update(self, product_id, data):
        if product_id not in self.products:
            return None
        product = self.products[product_id]
        for key in ["name", "description", "price", "category", "stock", "imageUrl"]:
            if key in data:
                product[key] = data[key]
        product["updatedAt"] = datetime.utcnow().isoformat() + "Z"
        return product

    def delete(self, product_id):
        return self.products.pop(product_id, None) is not None

    def check_stock(self, product_id, quantity):
        product = self.products.get(product_id)
        if not product:
            return False
        return product["stock"] >= quantity

    def decrement_stock(self, product_id, quantity):
        product = self.products.get(product_id)
        if product and product["stock"] >= quantity:
            product["stock"] -= quantity
            return True
        return False


# ---------------------------------------------------------------------------
# Cloud store adapters (students implement these for the assignment)
# ---------------------------------------------------------------------------

class DynamoDBStore:
    """
    AWS DynamoDB adapter.

    To use: set STORE_BACKEND=dynamodb and DYNAMODB_TABLE=<table-name>

    Credentials are never hardcoded. boto3 resolves them from the environment:
    ~/.aws/credentials when running locally, and the instance role / IRSA
    when running on AWS.
    """

    # Attributes a client is allowed to change through update()
    MUTABLE_FIELDS = ["name", "description", "price", "category", "stock", "imageUrl"]

    def __init__(self):
        import boto3

        table_name = os.environ.get("DYNAMODB_TABLE", "cloudmart-products")
        region = os.environ.get("AWS_REGION", "ap-southeast-1")
        self.table = boto3.resource("dynamodb", region_name=region).Table(table_name)
        logger.info("Using DynamoDB product store - table %s in %s", table_name, region)

    # -- type conversion ----------------------------------------------------
    # DynamoDB stores every number as Decimal. Flask cannot serialise Decimal,
    # and boto3 refuses to store float, so we translate at both boundaries.

    @staticmethod
    def _from_dynamo(value):
        if isinstance(value, Decimal):
            return int(value) if value % 1 == 0 else float(value)
        if isinstance(value, dict):
            return {k: DynamoDBStore._from_dynamo(v) for k, v in value.items()}
        if isinstance(value, list):
            return [DynamoDBStore._from_dynamo(v) for v in value]
        return value

    @staticmethod
    def _to_dynamo(value):
        if isinstance(value, float):
            return Decimal(str(value))
        if isinstance(value, dict):
            return {k: DynamoDBStore._to_dynamo(v) for k, v in value.items()}
        if isinstance(value, list):
            return [DynamoDBStore._to_dynamo(v) for v in value]
        return value

    # -- reads --------------------------------------------------------------

    def get_all(self, category=None, search=None):
        # Scan reads every item in the table, so it is billed per item read and
        # gets slower as the catalogue grows. Fine for a small catalogue; at
        # scale this wants a Global Secondary Index on the category attribute.
        items, kwargs = [], {}
        while True:
            response = self.table.scan(**kwargs)
            items.extend(response.get("Items", []))
            if "LastEvaluatedKey" not in response:
                break
            kwargs["ExclusiveStartKey"] = response["LastEvaluatedKey"]

        results = [self._from_dynamo(item) for item in items]

        if category:
            results = [p for p in results if p.get("category") == category]
        if search:
            query = search.lower()
            results = [
                p
                for p in results
                if query in str(p.get("name", "")).lower()
                or query in str(p.get("description", "")).lower()
            ]
        return results

    def get_by_id(self, product_id):
        item = self.table.get_item(Key={"id": product_id}).get("Item")
        return self._from_dynamo(item) if item else None

    # -- writes -------------------------------------------------------------

    def create(self, data):
        product = {
            "id": f"prod-{uuid.uuid4().hex[:6]}",
            "name": data["name"],
            "description": data.get("description", ""),
            "price": float(data["price"]),
            "category": data.get("category", "general"),
            "stock": int(data.get("stock", 0)),
            "imageUrl": data.get("imageUrl", ""),
            "createdAt": datetime.utcnow().isoformat() + "Z",
        }
        self.table.put_item(Item=self._to_dynamo(product))
        return product

    def update(self, product_id, data):
        if self.get_by_id(product_id) is None:
            return None

        updates = {key: data[key] for key in self.MUTABLE_FIELDS if key in data}
        updates["updatedAt"] = datetime.utcnow().isoformat() + "Z"

        # "name" and "stock" are DynamoDB reserved words, so attributes are
        # referenced through placeholders (#n0) instead of by literal name.
        names = {f"#n{i}": key for i, key in enumerate(updates)}
        values = {
            f":v{i}": self._to_dynamo(val) for i, val in enumerate(updates.values())
        }
        expression = "SET " + ", ".join(f"#n{i} = :v{i}" for i in range(len(updates)))

        response = self.table.update_item(
            Key={"id": product_id},
            UpdateExpression=expression,
            ExpressionAttributeNames=names,
            ExpressionAttributeValues=values,
            ReturnValues="ALL_NEW",
        )
        return self._from_dynamo(response["Attributes"])

    def delete(self, product_id):
        response = self.table.delete_item(
            Key={"id": product_id},
            ReturnValues="ALL_OLD",
        )
        return "Attributes" in response

    # -- stock --------------------------------------------------------------

    def check_stock(self, product_id, quantity):
        product = self.get_by_id(product_id)
        if not product:
            return False
        return int(product.get("stock", 0)) >= quantity

    def decrement_stock(self, product_id, quantity):
        from botocore.exceptions import ClientError

        # The read and the write happen as one atomic operation: DynamoDB
        # re-checks the stock level at write time and rejects the update if
        # another order got there first. Two customers cannot buy the last item.
        try:
            self.table.update_item(
                Key={"id": product_id},
                UpdateExpression="SET stock = stock - :qty",
                ConditionExpression="attribute_exists(id) AND stock >= :qty",
                ExpressionAttributeValues={":qty": quantity},
            )
            return True
        except ClientError as exc:
            if exc.response["Error"]["Code"] == "ConditionalCheckFailedException":
                logger.warning(
                    "Refused stock decrement for %s: not enough stock for %s units",
                    product_id,
                    quantity,
                )
                return False
            raise


class FirestoreStore:
    """
    GCP Firestore adapter.

    To use: set STORE_BACKEND=firestore and FIRESTORE_COLLECTION=<collection-name>

    Students: implement each method using google-cloud-firestore.
    Requires GCP Workload Identity for credentials.
    """

    def __init__(self):
        raise NotImplementedError(
            "Firestore store not implemented yet. "
            "See the assignment brief Section 3.3 for guidance."
        )


class CosmosDBStore:
    """
    Azure Cosmos DB adapter.

    To use: set STORE_BACKEND=cosmosdb and COSMOSDB_ENDPOINT / COSMOSDB_KEY

    Students: implement each method using azure-cosmos.
    Requires Azure Workload Identity for credentials.
    """

    def __init__(self):
        raise NotImplementedError(
            "Cosmos DB store not implemented yet. "
            "See the assignment brief Section 3.3 for guidance."
        )


def create_store():
    backend = os.environ.get("STORE_BACKEND", "memory").lower()
    if backend == "dynamodb":
        return DynamoDBStore()
    elif backend == "firestore":
        return FirestoreStore()
    elif backend == "cosmosdb":
        return CosmosDBStore()
    else:
        logger.info("Using in-memory product store (set STORE_BACKEND to use cloud DB)")
        return InMemoryStore()


store = create_store()

# ---------------------------------------------------------------------------
# Routes
# ---------------------------------------------------------------------------


@app.route("/health")
def health():
    """Health check endpoint for Kubernetes liveness/readiness probes."""
    return jsonify({"status": "healthy", "service": "product-service"})


@app.route("/ready")
def ready():
    """Readiness check — verifies the store is accessible."""
    try:
        store.get_all()
        return jsonify({"status": "ready", "service": "product-service"})
    except Exception as e:
        return jsonify({"status": "not ready", "error": str(e)}), 503


@app.route("/products", methods=["GET"])
def list_products():
    """
    List all products.
    Query params: ?category=electronics  &search=headphone
    """
    category = request.args.get("category")
    search = request.args.get("search")
    products = store.get_all(category=category, search=search)
    return jsonify({"products": products, "count": len(products)})


@app.route("/products/<product_id>", methods=["GET"])
def get_product(product_id):
    """Get a single product by ID."""
    product = store.get_by_id(product_id)
    if not product:
        abort(404, description=f"Product {product_id} not found")
    return jsonify(product)


@app.route("/products", methods=["POST"])
def create_product():
    """Create a new product."""
    data = request.get_json()
    if not data or "name" not in data or "price" not in data:
        abort(400, description="Missing required fields: name, price")
    product = store.create(data)
    logger.info(f"Created product: {product['id']} — {product['name']}")
    return jsonify(product), 201


@app.route("/products/<product_id>", methods=["PUT"])
def update_product(product_id):
    """Update an existing product."""
    data = request.get_json()
    if not data:
        abort(400, description="Request body required")
    product = store.update(product_id, data)
    if not product:
        abort(404, description=f"Product {product_id} not found")
    logger.info(f"Updated product: {product_id}")
    return jsonify(product)


@app.route("/products/<product_id>", methods=["DELETE"])
def delete_product(product_id):
    """Delete a product."""
    if not store.delete(product_id):
        abort(404, description=f"Product {product_id} not found")
    logger.info(f"Deleted product: {product_id}")
    return jsonify({"message": f"Product {product_id} deleted"}), 200


@app.route("/products/<product_id>/stock", methods=["GET"])
def check_stock(product_id):
    """Check stock availability (called by order-service)."""
    product = store.get_by_id(product_id)
    if not product:
        abort(404, description=f"Product {product_id} not found")
    return jsonify(
        {"productId": product_id, "stock": product["stock"], "available": product["stock"] > 0}
    )


@app.route("/products/<product_id>/stock/decrement", methods=["POST"])
def decrement_stock(product_id):
    """Decrement stock after order placement (called by order-service)."""
    data = request.get_json() or {}
    quantity = int(data.get("quantity", 1))
    if not store.decrement_stock(product_id, quantity):
        abort(409, description=f"Insufficient stock for product {product_id}")
    logger.info(f"Decremented stock for {product_id} by {quantity}")
    return jsonify({"message": "Stock updated", "productId": product_id})


@app.route("/categories", methods=["GET"])
def list_categories():
    """List all unique product categories."""
    products = store.get_all()
    categories = sorted(set(p["category"] for p in products))
    return jsonify({"categories": categories})


# ---------------------------------------------------------------------------
# Error handlers
# ---------------------------------------------------------------------------


@app.errorhandler(400)
def bad_request(e):
    return jsonify({"error": "Bad Request", "message": str(e.description)}), 400


@app.errorhandler(404)
def not_found(e):
    return jsonify({"error": "Not Found", "message": str(e.description)}), 404


@app.errorhandler(409)
def conflict(e):
    return jsonify({"error": "Conflict", "message": str(e.description)}), 409


@app.errorhandler(500)
def internal_error(e):
    logger.error(f"Internal Server Error: {e}")
    return jsonify({"error": "Internal Server Error"}), 500


# ---------------------------------------------------------------------------
# Entry point
# ---------------------------------------------------------------------------

if __name__ == "__main__":
    port = int(os.environ.get("PORT", 8001))
    debug = os.environ.get("FLASK_DEBUG", "false").lower() == "true"
    logger.info(f"Starting product-service on port {port}")
    app.run(host="0.0.0.0", port=port, debug=debug)
