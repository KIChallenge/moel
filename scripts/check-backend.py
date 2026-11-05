#!/usr/bin/env python3
"""Dependency-free PHP lint, mocked intake checks and real HTTP boundary checks."""
import json
import os
from pathlib import Path
import shutil
import socket
import subprocess
import tempfile
import time
import urllib.error
import urllib.request

root = Path(__file__).resolve().parents[1]
php = shutil.which("php")
if not php:
    raise SystemExit("PHP 8.2+ is required. No OpenAI key is needed for these checks.")
backend = root / "apps/backend/sovi.php"
tests = root / "apps/backend/tests/check.php"
for path in (backend, tests, backend.parent / "config.example.php", backend.parent / "index.php"):
    subprocess.run([php, "-l", str(path)], check=True)
subprocess.run([php, str(tests)], check=True)

with socket.socket() as listener:
    listener.bind(("127.0.0.1", 0))
    port = listener.getsockname()[1]
token = "test-only-" + "a" * 40
env = {**os.environ, "SOVI_API_TOKEN": token, "OPENAI_API_KEY": "test-only-never-used",
       "SOVI_ALLOWED_ORIGIN": "https://sovi.example"}
with tempfile.TemporaryFile() as server_log, tempfile.TemporaryDirectory() as private:
    config = Path(private) / "config.php"
    shutil.copyfile(backend.parent / "config.example.php", config)
    env["SOVI_CONFIG_FILE"] = str(config)
    process = subprocess.Popen([php, "-S", f"127.0.0.1:{port}", "-t", str(backend.parent)],
                               env=env, stdout=server_log, stderr=server_log)
    url = f"http://127.0.0.1:{port}/sovi.php"

    def request(method="GET", data=None, headers=None, suffix=""):
        req = urllib.request.Request(url + suffix, data=data, method=method, headers=headers or {})
        try:
            response = urllib.request.urlopen(req, timeout=2)
        except urllib.error.HTTPError as error:
            response = error
        with response:
            body = response.read()
            return response.status, response.headers, json.loads(body) if body else None

    try:
        for _ in range(50):
            try:
                status, headers, body = request()
                break
            except urllib.error.URLError:
                if process.poll() is not None:
                    raise RuntimeError("PHP development server could not start")
                time.sleep(0.05)
        else:
            raise RuntimeError("PHP development server did not become ready")
        assert status == 200 and body["service"] == "sovi-intake"
        assert "no-store" in headers["Cache-Control"]
        assert "X-Powered-By" not in headers
        for entry in ("", "index.php"):
            entry_url = f"http://127.0.0.1:{port}/{entry}"
            with urllib.request.urlopen(entry_url, timeout=2) as response:
                assert json.load(response)["service"] == "sovi-intake"
            try:
                urllib.request.urlopen(urllib.request.Request(entry_url, data=b"{}", method="POST"), timeout=2)
            except urllib.error.HTTPError as error:
                assert error.code == 401 and json.load(error)["error"]["code"] == "unauthorized"
            else:
                raise AssertionError("Entry point bypassed token authentication")
        assert request("POST", b"{}")[0] == 401
        auth = {"Authorization": f"Bearer {token}", "Content-Type": "application/json"}
        assert request("POST", b"{broken", auth)[2]["error"]["code"] == "invalid_json"
        without_consent = json.dumps({"locale": "de", "messages": [{"role": "user", "content": "Physio"}]}).encode()
        assert request("POST", without_consent, auth)[2]["error"]["code"] == "consent_required"
        assert request("POST", b"x" * 32769, auth)[0] == 413
        assert request("POST", b"{}", {**auth, "Content-Type": "text/plain"})[0] == 415
        assert request("PUT")[0] == 405
        assert request(headers={"Origin": "https://untrusted.example"})[0] == 403
        status, headers, _ = request("OPTIONS", headers={"Origin": "https://sovi.example"})
        assert status == 204 and headers["Access-Control-Allow-Origin"] == "https://sovi.example"
        assert request("POST", b"{}", auth, "?action=search")[0] == 404
        assert request("POST", without_consent, auth, "?action=chat")[2]["error"]["code"] == "consent_required"
        invalid_location = {"locale": "en", "cloud_processing_consent": True,
                            "messages": [{"role": "user", "content": "Find a pharmacy"}],
                            "location": {"latitude": 999, "longitude": 16}}
        assert request("POST", json.dumps(invalid_location).encode(), auth)[2]["error"]["code"] == "invalid_location"
        config.unlink()
        assert request()[0] == 503
        print("HTTP boundary checks passed: 19 (no external API requests)")
    finally:
        process.terminate()
        process.wait(timeout=5)
