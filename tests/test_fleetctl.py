import importlib.util
import unittest
from pathlib import Path


MODULE_PATH = Path(__file__).resolve().parents[1] / "scripts" / "fleetctl.py"
SPEC = importlib.util.spec_from_file_location("fleetctl", MODULE_PATH)
assert SPEC is not None and SPEC.loader is not None
fleetctl = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(fleetctl)


class FleetConfigTests(unittest.TestCase):
    def setUp(self):
        self.config = fleetctl.load_config(fleetctl.DEFAULT_CONFIG)

    def test_checked_in_inventory_has_two_nodes(self):
        self.assertEqual(len(self.config["nodes"]), 2)

    def test_select_node_returns_requested_node(self):
        node = fleetctl.select_node(self.config, "fleet-node-1")
        self.assertEqual(node["host"], "192.168.252.3")

    def test_select_node_rejects_unknown_node(self):
        with self.assertRaisesRegex(ValueError, "unknown node"):
            fleetctl.select_node(self.config, "missing-node")

    def test_local_command_uses_bash(self):
        command = fleetctl.remote_command(
            {"name": "control-node", "host": "127.0.0.1", "local": True},
            "hostname",
        )
        self.assertEqual(command, ["bash", "-lc", "hostname"])

    def test_remote_command_enforces_batch_ssh(self):
        node = fleetctl.select_node(self.config, "fleet-node-1")
        command = fleetctl.remote_command(node, "hostname")
        self.assertEqual(command[0], "ssh")
        self.assertIn("BatchMode=yes", command)
        self.assertIn("ubuntu@192.168.252.3", command)


if __name__ == "__main__":
    unittest.main()
