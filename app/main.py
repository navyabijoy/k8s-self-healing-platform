import logging
import math
import os
import threading
import time
from contextlib import asynccontextmanager
from datetime import datetime, timezone
from typing import Annotated

import psycopg2
from psycopg2.pool import ThreadedConnectionPool
from fastapi import FastAPI, HTTPException, Query, Request
from fastapi.responses import PlainTextResponse
from prometheus_client import (
    CONTENT_TYPE_LATEST,
    Counter,
    Gauge,
    Histogram,
    generate_latest,
)

logger = logging.getLogger(__name__)
logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s %(levelname)s %(name)s %(message)s",
)

# Application Metrics
REQUEST_COUNT = Counter(
    "app_requests_total",
    "Total HTTP requests",
    ["method", "path", "status"],
)
REQUEST_LATENCY = Histogram(
    "app_request_duration_seconds",
    "HTTP request latency",
    ["path"],
    buckets=[0.005, 0.01, 0.025, 0.05, 0.1, 0.25, 0.5, 1.0, 2.5, 5.0],
)
ACTIVE_REQUESTS = Gauge("app_active_requests", "In-flight requests")
DB_CONNECT_OK  = Counter("app_db_connections_total", "Successful DB pings")
DB_CONNECT_ERR = Counter("app_db_connection_errors_total", "Failed DB pings")
CPU_LOAD_ACTIVE = Gauge("app_cpu_load_active", "1 while stress thread is running")


@asynccontextmanager
async def lifespan(app: FastAPI):
    logger.info(
        "starting pod=%s node=%s ns=%s env=%s",
        os.getenv("POD_NAME", "-"),
        os.getenv("NODE_NAME", "-"),
        os.getenv("POD_NAMESPACE", "-"),
        os.getenv("ENVIRONMENT", "dev"),
    )
    
    # Initialize database connection pool
    dsn = dict(
        host=os.getenv("DB_HOST", "postgres-service"),
        port=int(os.getenv("DB_PORT", "5432")),
        dbname=os.getenv("DB_NAME", "appdb"),
        user=os.getenv("DB_USER", "appuser"),
        password=os.getenv("DB_PASSWORD", ""),
        connect_timeout=5,
    )
    try:
        app.state.db_pool = ThreadedConnectionPool(
            minconn=1,
            maxconn=10,
            **dsn
        )
        logger.info("Database connection pool initialized successfully")
    except Exception as exc:
        logger.error("Failed to initialize database connection pool: %s", exc)
        app.state.db_pool = None

    yield
    
    if app.state.db_pool:
        app.state.db_pool.closeall()
        logger.info("Database connection pool closed")


app = FastAPI(
    title="self-healing-eks",
    version="1.0.0",
    docs_url="/docs",
    redoc_url=None,
    lifespan=lifespan,
)


@app.middleware("http")
async def metrics_middleware(request: Request, call_next):
    ACTIVE_REQUESTS.inc()
    t0 = time.perf_counter()
    response = await call_next(request)
    elapsed = time.perf_counter() - t0
    path = request.url.path
    REQUEST_COUNT.labels(request.method, path, response.status_code).inc()
    REQUEST_LATENCY.labels(path).observe(elapsed)
    ACTIVE_REQUESTS.dec()
    return response


@app.get("/", include_in_schema=False)
async def root():
    return {
        "service": "self-healing-eks",
        "version": "1.0.0",
        "pod":  os.getenv("POD_NAME", "-"),
        "node": os.getenv("NODE_NAME", "-"),
        "ts":   datetime.now(timezone.utc).isoformat(),
    }


@app.get("/health", tags=["ops"])
async def health():
    """Kubernetes liveness and readiness probe endpoint."""
    return {"status": "ok", "ts": datetime.now(timezone.utc).isoformat()}


@app.get("/version", tags=["ops"])
async def version():
    """Returns build metadata injected at container image build time."""
    return {
        "version":     "1.0.0",
        "build_time":  os.getenv("BUILD_TIME", "-"),
        "git_commit":  os.getenv("GIT_COMMIT", "-"),
        "environment": os.getenv("ENVIRONMENT", "dev"),
        "pod":         os.getenv("POD_NAME", "-"),
        "node":        os.getenv("NODE_NAME", "-"),
    }


@app.get("/metrics", tags=["ops"], include_in_schema=False)
async def metrics():
    """Prometheus scrape endpoint."""
    return PlainTextResponse(generate_latest(), media_type=CONTENT_TYPE_LATEST)


@app.get("/db", tags=["ops"])
async def db_check(request: Request):
    """Verifies connection health to the PostgreSQL database."""
    pool: ThreadedConnectionPool = getattr(request.app.state, "db_pool", None)
    if not pool:
        DB_CONNECT_ERR.inc()
        raise HTTPException(status_code=503, detail="Database connection pool is not initialized")
    
    conn = None
    try:
        conn = pool.getconn()
        with conn.cursor() as cur:
            cur.execute("SELECT version();")
            db_version = cur.fetchone()[0]
        pool.putconn(conn)
        DB_CONNECT_OK.inc()
        return {"status": "connected", "server": db_version}
    except Exception as exc:
        DB_CONNECT_ERR.inc()
        if conn:
            try:
                pool.putconn(conn)
            except Exception:
                pass
        logger.error("Database connection check failed: %s", exc)
        raise HTTPException(status_code=503, detail=str(exc)) from exc


@app.post("/load", tags=["chaos"])
async def simulate_load(
    seconds: Annotated[int, Query(ge=1, le=300)] = 30,
):
    """Simulates CPU load to trigger autoscaling and alerting."""
    logger.warning("cpu stress requested duration=%ds", seconds)
    CPU_LOAD_ACTIVE.set(1)

    def _burn():
        deadline = time.monotonic() + seconds
        while time.monotonic() < deadline:
            math.factorial(10_000)
        CPU_LOAD_ACTIVE.set(0)
        logger.info("cpu stress finished")

    threading.Thread(target=_burn, daemon=True, name="cpu-stress").start()
    return {"status": "started", "duration_seconds": seconds}


@app.get("/crash", tags=["chaos"])
async def crash():
    """Terminates the process immediately to simulate a pod failure."""
    logger.critical("intentional crash triggered — process exiting")
    os._exit(1)
