# ---- Stage 1: Build dependencies ----
FROM python:3.11-alpine AS builder

WORKDIR /build
COPY requirements.txt .
RUN pip install --no-cache-dir --prefix=/install -r requirements.txt

# ---- Stage 2: Runtime ----
FROM python:3.11-alpine

# Create non-root user (busybox syntax - Alpine has no groupadd/useradd)
RUN addgroup -S appuser && adduser -S appuser -G appuser

WORKDIR /app

# Copy installed packages from builder
COPY --from=builder /install /usr/local

# Copy application code
COPY app.py .

# Switch to non-root user
USER appuser

EXPOSE 8001

# Health check for container orchestrators
HEALTHCHECK --interval=30s --timeout=3s --start-period=10s --retries=3 \
  CMD python -c "import urllib.request; urllib.request.urlopen('http://127.0.0.1:8001/health')" || exit 1

CMD ["gunicorn", "--bind", "0.0.0.0:8001", "--workers", "2", "--access-logfile", "-", "app:app"]
