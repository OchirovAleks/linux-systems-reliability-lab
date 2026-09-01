#!/usr/bin/env python3

"""Operate and diagnose nodes in the Linux reliability lab fleet."""

from __future__ import annotations

import argparse
import concurrent.futures
import json
import shlex
import socket
import subprocess
import sys
import urllib.error
import urllib.request
from pathlib import Path
from typing import Any


DEFAULT_CONFIG = Path(__file__).resolve().parents[1] / "config" / "fleet.json"
DIAGNOSTIC_COMMAND = r"""
printf 'hostname: '; hostname
printf 'kernel: '; uname -r
printf 'uptime: '; uptime -p
printf 'service: '; systemctl is-active reliability-web || true
printf 'node_exporter: '; systemctl is-active prometheus-node-exporter || true
printf '\nfailed units:\n'; systemctl --failed --no-pager || true
printf '\ndisk:\n'; df -h /
printf '\nmemory:\n'; free -h
printf '\nlistening ports:\n'; ss -ltn | grep -E ':(8080|9100)[[:space:]]' || true
printf '\nrecent service logs:\n'; journalctl -u reliability-web -n 8 --no-pager || true
""".strip()


def load_config(path: Path) -> dict[str, Any]:
    with path.open(encoding="utf-8") as config_file:
        config = json.load(config_file)

    nodes = config.get("nodes")
    if not isinstance(nodes, list) or not nodes:
        raise ValueError("fleet configuration must contain a non-empty nodes list")

    required = {"name", "host"}
    for node in nodes:
        missing = required - node.keys()
        if missing:
            raise ValueError(
                f"node is missing required fields: {', '.join(sorted(missing))}"
            )

    return config


def select_node(config: dict[str, Any], name: str) -> dict[str, Any]:
    for node in config["nodes"]:
        if node["name"] == name:
            return node
    available = ", ".join(node["name"] for node in config["nodes"])
    raise ValueError(f"unknown node {name!r}; available nodes: {available}")


def check_http(host: str, port: int, timeout: float) -> tuple[bool, str]:
    url = f"http://{host}:{port}/"
    request = urllib.request.Request(url, method="GET")
    try:
        with urllib.request.urlopen(request, timeout=timeout) as response:
            return response.status == 200, f"HTTP {response.status}"
    except (urllib.error.URLError, TimeoutError, socket.timeout) as error:
        return False, str(error.reason if isinstance(error, urllib.error.URLError) else error)


def check_tcp(host: str, port: int, timeout: float) -> tuple[bool, str]:
    try:
        with socket.create_connection((host, port), timeout=timeout):
            return True, "open"
    except OSError as error:
        return False, str(error)


def check_node(
    node: dict[str, Any], service_port: int, metrics_port: int, timeout: float
) -> dict[str, Any]:
    web_ok, web_detail = check_http(node["host"], service_port, timeout)
    metrics_ok, metrics_detail = check_tcp(node["host"], metrics_port, timeout)
    return {
        "name": node["name"],
        "host": node["host"],
        "web": "UP" if web_ok else "DOWN",
        "web_detail": web_detail,
        "metrics": "UP" if metrics_ok else "DOWN",
        "metrics_detail": metrics_detail,
        "healthy": web_ok and metrics_ok,
    }


def remote_command(node: dict[str, Any], command: str) -> list[str]:
    if node.get("local"):
        return ["bash", "-lc", command]

    ssh_user = node.get("ssh_user", "ubuntu")
    ssh_key = node.get("ssh_key")
    ssh_command = [
        "ssh",
        "-o",
        "BatchMode=yes",
        "-o",
        "ConnectTimeout=5",
        "-o",
        "StrictHostKeyChecking=accept-new",
    ]
    if ssh_key:
        ssh_command.extend(["-i", ssh_key])
    ssh_command.extend(
        [f"{ssh_user}@{node['host']}", f"bash -lc {shlex.quote(command)}"]
    )
    return ssh_command


def run_on_node(node: dict[str, Any], command: str) -> int:
    result = subprocess.run(remote_command(node, command), check=False)
    return result.returncode


def print_inventory(config: dict[str, Any]) -> int:
    print(f"{'NODE':<20} {'HOST':<16} {'CONNECTION':<12}")
    for node in config["nodes"]:
        connection = "local" if node.get("local") else "ssh"
        print(f"{node['name']:<20} {node['host']:<16} {connection:<12}")
    return 0


def print_health(config: dict[str, Any], timeout: float, as_json: bool) -> int:
    nodes = config["nodes"]
    with concurrent.futures.ThreadPoolExecutor(max_workers=len(nodes)) as executor:
        futures = [
            executor.submit(
                check_node,
                node,
                int(config["service_port"]),
                int(config["metrics_port"]),
                timeout,
            )
            for node in nodes
        ]
        results = [future.result() for future in futures]

    if as_json:
        print(json.dumps(results, indent=2))
    else:
        print(f"{'NODE':<20} {'HOST':<16} {'WEB':<8} {'METRICS':<8} DETAILS")
        for result in results:
            details = f"web={result['web_detail']}; metrics={result['metrics_detail']}"
            print(
                f"{result['name']:<20} {result['host']:<16} "
                f"{result['web']:<8} {result['metrics']:<8} {details}"
            )

    return 0 if all(result["healthy"] for result in results) else 1


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--config",
        type=Path,
        default=DEFAULT_CONFIG,
        help=f"fleet configuration path (default: {DEFAULT_CONFIG})",
    )
    subparsers = parser.add_subparsers(dest="command", required=True)

    subparsers.add_parser("inventory", help="list configured fleet nodes")

    health_parser = subparsers.add_parser("health", help="check all fleet nodes")
    health_parser.add_argument("--timeout", type=float, default=3.0)
    health_parser.add_argument("--json", action="store_true", dest="as_json")

    diagnose_parser = subparsers.add_parser(
        "diagnose", help="collect diagnostic evidence from one node"
    )
    diagnose_parser.add_argument("node")

    for action in ("start", "stop", "restart"):
        action_parser = subparsers.add_parser(
            action, help=f"{action} the web service on one node"
        )
        action_parser.add_argument("node")
        action_parser.add_argument(
            "--yes", action="store_true", help=f"confirm the service {action}"
        )
    return parser


def main() -> int:
    parser = build_parser()
    args = parser.parse_args()

    try:
        config = load_config(args.config)
        if args.command == "inventory":
            return print_inventory(config)
        if args.command == "health":
            return print_health(config, args.timeout, args.as_json)

        node = select_node(config, args.node)
        if args.command == "diagnose":
            return run_on_node(node, DIAGNOSTIC_COMMAND)
        if args.command in {"start", "stop", "restart"}:
            if not args.yes:
                parser.error(f"{args.command} requires --yes")
            command = (
                f"sudo -n systemctl {args.command} reliability-web; "
                "action_status=$?; "
                "systemctl is-active reliability-web || true; "
                "exit $action_status"
            )
            return run_on_node(node, command)
    except (OSError, ValueError, json.JSONDecodeError) as error:
        print(f"fleetctl: {error}", file=sys.stderr)
        return 2

    return 2


if __name__ == "__main__":
    raise SystemExit(main())
