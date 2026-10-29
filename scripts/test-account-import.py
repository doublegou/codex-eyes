#!/usr/bin/env python3
"""Offline integration check for the pinned helper. Uses synthetic tokens and an isolated home."""
import base64
import json
import os
import pathlib
import platform
import subprocess
import sys
import tempfile

root = pathlib.Path(__file__).resolve().parents[1]
architecture = "arm64" if platform.machine() == "arm64" else "x86_64"
helper = pathlib.Path(sys.argv[1]).resolve() if len(sys.argv) > 1 else root / "ThirdParty" / "bin" / architecture / "codex-auth"

def auth(user):
    claims = {"email": user + "@example.com", "https://api.openai.com/auth": {
        "chatgpt_user_id": user, "chatgpt_account_id": "account-" + user, "chatgpt_plan_type": "plus"}}
    token = "header." + base64.urlsafe_b64encode(json.dumps(claims).encode()).decode().rstrip("=") + ".signature"
    return json.dumps({"auth_mode": "chatgpt", "tokens": {"id_token": token, "access_token": token,
                      "refresh_token": "synthetic-only", "account_id": "account-" + user}}).encode()

with tempfile.TemporaryDirectory(prefix="eyes-import-test-") as directory:
    os.chmod(directory, 0o700)
    login = pathlib.Path(directory) / "auth.json"
    environment = {**os.environ, "CODEX_HOME": directory, "HOME": directory, "NO_COLOR": "1"}
    for count, user in enumerate(["sample-one", "sample-two"], 1):
        login.write_bytes(auth(user)); login.chmod(0o600)
        original = login.read_bytes()
        result = subprocess.run([str(helper), "list", "--skip-api", "--json"], env=environment,
                                capture_output=True, timeout=10, check=True)
        accounts = json.loads(result.stdout)
        assert len(accounts["accounts"]) == count, "Previously imported account was not retained"
        assert accounts["active_account_key"].startswith(user + "::"), "Active identity mismatch"
        assert login.read_bytes() == original, "The source login file was modified"
print("PASS: external logins imported, previous accounts retained, source login unchanged; no API calls")
