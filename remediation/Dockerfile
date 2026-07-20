# syntax=docker/dockerfile:1
FROM python:3.12-slim

RUN apt-get update && apt-get install -y --no-install-recommends curl \
    && rm -rf /var/lib/apt/lists/* \
    && groupadd -r botuser \
    && useradd -r -g botuser -d /app -s /sbin/nologin botuser

WORKDIR /app

COPY requirements.txt .
RUN pip install --no-cache-dir --upgrade pip && \
    pip install --no-cache-dir -r requirements.txt

COPY --chown=botuser:botuser . .

USER botuser
EXPOSE 9000

HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
    CMD curl -sf http://localhost:9000/health || exit 1

# gunicorn provides worker management and graceful reload; flask dev server is
# single-threaded and not safe for concurrent webhook delivery from Alertmanager.
CMD ["gunicorn", "webhook_server:app", "--bind", "0.0.0.0:9000", "--workers", "2", "--timeout", "30", "--access-logfile", "-"]
