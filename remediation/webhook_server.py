import logging
import os
from collections import deque
from datetime import datetime, timezone
from threading import Lock

from flask import Flask, request, jsonify

from remediation_bot import handle_alert

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s %(levelname)s %(name)s %(message)s",
)
logger = logging.getLogger(__name__)

app = Flask(__name__)

_log_lock = Lock()
_action_log: deque = deque(maxlen=100)


@app.get("/health")
def health():
    return {"status": "ok", "ts": datetime.now(timezone.utc).isoformat()}


@app.post("/webhook")
def webhook():
    """
    Webhook endpoint for receiving alerts from Alertmanager.
    """
    if not request.is_json:
        return jsonify({"error": "expected application/json"}), 415

    payload = request.get_json(force=True)
    alerts  = payload.get("alerts", [])
    results = []

    for raw in alerts:
        alert = {
            "alertname": raw.get("labels", {}).get("alertname", ""),
            "labels":    raw.get("labels", {}),
            "status":    raw.get("status", ""),
        }
        result = handle_alert(alert)
        entry  = {"alert": alert["alertname"], "status": alert["status"], "result": result,
                  "ts": datetime.now(timezone.utc).isoformat()}
        with _log_lock:
            _action_log.append(entry)
        results.append(entry)

    return jsonify({"processed": len(results), "results": results}), 200


@app.post("/trigger")
def trigger():
    """
    Manual remediation trigger for testing.
    """
    body   = request.get_json(force=True)
    result = handle_alert({
        "alertname": body.get("alertname", ""),
        "labels":    body.get("labels", {}),
        "status":    "firing",
    })
    return jsonify(result), 200


@app.get("/log")
def get_log():
    """Returns a log of the last 100 remediation actions."""
    with _log_lock:
        entries = list(_action_log)
    return jsonify({"count": len(entries), "entries": entries}), 200


if __name__ == "__main__":
    port = int(os.getenv("PORT", "9000"))
    app.run(host="0.0.0.0", port=port, threaded=True)
