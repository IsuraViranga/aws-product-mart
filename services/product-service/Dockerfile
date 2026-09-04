FROM python:3.11-slim AS builder

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1

WORKDIR /build

COPY requirements.txt .
RUN pip install --no-cache-dir --prefix=/install -r requirements.txt

FROM python:3.11-slim AS runtime

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1

RUN groupadd --system appuser \
    && useradd --system --gid appuser --create-home --home-dir /app appuser

WORKDIR /app

COPY --from=builder /install /usr/local
COPY --chown=appuser:appuser app.py dynamodb.py env_loader.py .

USER appuser

EXPOSE 8001

HEALTHCHECK --interval=30s --timeout=3s --start-period=10s --retries=3 \
  CMD python -c "import urllib.request; urllib.request.urlopen('http://127.0.0.1:8001/health')"

CMD ["gunicorn", "--bind", "0.0.0.0:8001", "--workers", "2", "--access-logfile", "-", "app:app"]
