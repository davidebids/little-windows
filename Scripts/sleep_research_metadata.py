"""Compatibility checks for research artifacts written by earlier runners."""


def care_exposure(result):
    declared = result.get("audit", {}).get("careExposure")
    running = any(str(name).endswith(("Running", "RunningElapsed")) for name in result.get("featureNames", []))
    if declared not in [None, "started", "completed"]:
        raise ValueError("Unknown care exposure")
    if declared == "completed" and running:
        raise ValueError("Running-care features contradict completed-only provenance")
    return declared or ("started" if running else "completed")
