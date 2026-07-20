import datetime
import logging
from typing import Any, Dict, Optional, Tuple

from kubernetes import client, config
from kubernetes.client.rest import ApiException

logger = logging.getLogger(__name__)

_core_v1: Optional[client.CoreV1Api] = None
_apps_v1: Optional[client.AppsV1Api] = None


def _get_clients() -> Tuple[client.CoreV1Api, client.AppsV1Api]:
    global _core_v1, _apps_v1
    if _core_v1 is None:
        try:
            config.load_incluster_config()
        except config.ConfigException:
            config.load_kube_config()
        _core_v1 = client.CoreV1Api()
        _apps_v1 = client.AppsV1Api()
    return _core_v1, _apps_v1


def _resolve_deployment_from_pod(namespace: str, pod_name: str) -> Optional[str]:
    """
    Resolves the parent deployment name for a given pod by traversing owner references.
    """
    core_v1, apps_v1 = _get_clients()
    try:
        pod = core_v1.read_namespaced_pod(name=pod_name, namespace=namespace)
        if not pod.metadata.owner_references:
            return None
        
        rs_name = None
        for ref in pod.metadata.owner_references:
            if ref.kind == "ReplicaSet":
                rs_name = ref.name
                break
        
        if not rs_name:
            return None
        
        rs = apps_v1.read_namespaced_replica_set(name=rs_name, namespace=namespace)
        if not rs.metadata.owner_references:
            return None
        
        for ref in rs.metadata.owner_references:
            if ref.kind == "Deployment":
                return ref.name
                
        return None
    except ApiException as exc:
        logger.error("Failed to resolve deployment for pod=%s: %s", pod_name, exc)
        return None


def _resolve_deployment(namespace: str, labels: Dict[str, Any]) -> str:
    """
    Resolves the deployment name dynamically from alert labels.
    """
    pod_name = labels.get("pod")
    if pod_name:
        resolved = _resolve_deployment_from_pod(namespace, pod_name)
        if resolved:
            return resolved
            
    if "deployment" in labels:
        return labels["deployment"]
        
    if "container" in labels:
        return labels["container"]
        
    return "demo-app"


def restart_crashing_pod(namespace: str, pod_name: str) -> Dict[str, Any]:
    """
    Deletes a crash-looping pod to reset Kubernetes' exponential backoff timer.
    """
    core_v1, _ = _get_clients()
    logger.info("Restarting pod ns=%s pod=%s", namespace, pod_name)
    try:
        core_v1.delete_namespaced_pod(
            name=pod_name,
            namespace=namespace,
            body=client.V1DeleteOptions(grace_period_seconds=0),
        )
        return _result("restart_pod", namespace=namespace, pod=pod_name)
    except ApiException as exc:
        if exc.status == 404:
            logger.warning("Pod already gone ns=%s pod=%s", namespace, pod_name)
            return _result("restart_pod", status="skipped", reason="pod_not_found")
        return _error("restart_pod", exc)


def scale_up_deployment(
    namespace: str,
    deployment: str,
    increment: int = 1,
    max_replicas: int = 10,
) -> Dict[str, Any]:
    """Increments the replica count of a deployment, capped at max_replicas."""
    _, apps_v1 = _get_clients()
    logger.info("Scaling deployment ns=%s deploy=%s +%d", namespace, deployment, increment)
    try:
        deploy_obj = apps_v1.read_namespaced_deployment(deployment, namespace)
        current = deploy_obj.spec.replicas or 1
        target = min(current + increment, max_replicas)
        if target == current:
            return _result("scale_up", status="skipped", reason=f"already_at_max_{max_replicas}")
        
        apps_v1.patch_namespaced_deployment(
            deployment, namespace, body={"spec": {"replicas": target}}
        )
        logger.info("Scaled ns=%s deploy=%s %d->%d", namespace, deployment, current, target)
        return _result("scale_up", namespace=namespace, deployment=deployment,
                       previous=current, current=target)
    except ApiException as exc:
        return _error("scale_up", exc)


def increase_memory_limit(
    namespace: str,
    deployment: str,
    container: str,
    factor: float = 1.25,
) -> Dict[str, Any]:
    """
    Increases a container's memory limit by the specified factor.
    """
    _, apps_v1 = _get_clients()
    logger.info("Patching memory ns=%s deploy=%s container=%s factor=%.2f",
                namespace, deployment, container, factor)
    try:
        spec = apps_v1.read_namespaced_deployment(deployment, namespace).spec
        target_container = next(
            (c for c in spec.template.spec.containers if c.name == container), None
        )
        if target_container is None:
            return _error("increase_memory", Exception(f"container {container!r} not found"))

        current_limit = target_container.resources.limits.get("memory", "256Mi")
        new_limit = _bytes_to_mi(_parse_mi(current_limit) * factor)
        new_request = _bytes_to_mi(_parse_mi(new_limit) * 0.75)

        apps_v1.patch_namespaced_deployment(
            deployment,
            namespace,
            body={"spec": {"template": {"spec": {"containers": [{
                "name": container,
                "resources": {
                    "limits": {"memory": new_limit},
                    "requests": {"memory": new_request},
                },
            }]}}}},
        )
        logger.info("Patched memory ns=%s deploy=%s %s->%s",
                    namespace, deployment, current_limit, new_limit)
        return _result("increase_memory", namespace=namespace, deployment=deployment,
                       previous=current_limit, current=new_limit)
    except ApiException as exc:
        return _error("increase_memory", exc)


def cordon_node(node_name: str) -> Dict[str, Any]:
    """
    Marks a node unschedulable to prevent new workloads from landing on a degraded host.
    """
    core_v1, _ = _get_clients()
    logger.info("Cordoning node=%s", node_name)
    try:
        core_v1.patch_node(node_name, body={"spec": {"unschedulable": True}})
        return _result("cordon_node", node=node_name)
    except ApiException as exc:
        return _error("cordon_node", exc)


# Alert dispatch handler registration
_ALERT_HANDLERS = {
    "KubePodCrashLooping":    lambda ns, labels: restart_crashing_pod(
                                  ns,
                                  labels["pod"],
                              ),
    "PodOOMKilled":           lambda ns, labels: {
                                  "scale": scale_up_deployment(ns, _resolve_deployment(ns, labels)),
                                  "memory": increase_memory_limit(ns, _resolve_deployment(ns, labels), labels.get("container", _resolve_deployment(ns, labels))),
                              },
    "HighCPUUtilization":     lambda ns, labels: scale_up_deployment(ns, _resolve_deployment(ns, labels)),
    "HighLatency":            lambda ns, labels: scale_up_deployment(ns, _resolve_deployment(ns, labels)),
    "HighMemoryUtilization":  lambda ns, labels: increase_memory_limit(
                                  ns, _resolve_deployment(ns, labels), labels.get("container", _resolve_deployment(ns, labels))
                              ),
    "NodeNotReady":           lambda ns, labels: cordon_node(labels["node"]),
}


def handle_alert(alert: Dict[str, Any]) -> Dict[str, Any]:
    """
    Routes an Alertmanager alert payload to the appropriate remediation handler.
    """
    name   = alert.get("alertname", "")
    labels = alert.get("labels", {})
    status = alert.get("status", "firing")
    ns     = labels.get("namespace", "app")

    logger.info("Received alert name=%s status=%s namespace=%s", name, status, ns)

    if status != "firing":
        return {"action": "none", "reason": "resolved"}

    handler = _ALERT_HANDLERS.get(name)
    if handler is None:
        logger.warning("No handler registered for alert=%s", name)
        return {"action": "none", "reason": f"unhandled_alert:{name}"}

    try:
        return handler(ns, labels)
    except KeyError as exc:
        missing_label = str(exc)
        logger.error("Alert=%s missing required label %s", name, missing_label)
        return _error("dispatch", Exception(f"missing label: {missing_label}"))
    except Exception as exc:
        logger.exception("Unhandled error during remediation alert=%s", name)
        return _error("dispatch", exc)


def _result(action: str, status: str = "success", **kwargs: Any) -> Dict[str, Any]:
    return {
        "action": action,
        "status": status,
        "ts": datetime.datetime.now(datetime.timezone.utc).isoformat(),
        **kwargs,
    }


def _error(action: str, exc: Exception) -> Dict[str, Any]:
    logger.error("Action=%s error=%s", action, exc)
    return {"action": action, "status": "error", "error": str(exc)}


def _parse_mi(s: str) -> float:
    """Parses a Kubernetes quantity string to bytes."""
    s = s.strip()
    units = {"Ki": 2**10, "Mi": 2**20, "Gi": 2**30, "K": 1e3, "M": 1e6, "G": 1e9}
    for suffix, mult in units.items():
        if s.endswith(suffix):
            return float(s[: -len(suffix)]) * mult
    return float(s)


def _bytes_to_mi(b: float) -> str:
    """Converts bytes to a Kubernetes MiB quantity string."""
    return f"{int(b / 2**20)}Mi"
