#!/usr/bin/env python3
"""Exercise the real .htaccess in a private Apache server using harmless fixtures.

No PHP module, production config, root privileges or outbound network is used.
This checks Apache access rules; check-backend.py checks the actual PHP handlers.
"""
import getpass
import grp
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
httpd = os.environ.get("APACHE_HTTPD") or shutil.which("httpd") or shutil.which("apache2")
if not httpd and Path("/usr/sbin/httpd").exists():
    httpd = "/usr/sbin/httpd"
module_candidates = [os.environ.get("APACHE_MODULE_DIR", ""), "/usr/libexec/apache2", "/usr/lib/apache2/modules"]
modules = next((Path(p) for p in module_candidates if p and (Path(p) / "mod_rewrite.so").is_file()), None)
if not httpd or not modules:
    raise SystemExit("Apache 2.4 required; optionally set APACHE_HTTPD and APACHE_MODULE_DIR.")

with socket.socket() as listener:
    listener.bind(("127.0.0.1", 0))
    port = listener.getsockname()[1]

with tempfile.TemporaryDirectory(prefix="sovi-apache-") as directory:
    private = Path(directory)
    web = private / "htdocs"
    api = web / "sovi-api"
    (api / "tests").mkdir(parents=True)
    shutil.copyfile(root / "apps/backend/.htaccess", api / ".htaccess")
    # Intentionally not real PHP files/config. A static handler lets us detect
    # disclosure if an allowlist fails, without ever exposing an actual secret.
    for name, content in {"index.php": "entrypoint", "sovi.php": "legacy-endpoint",
                          "config.php": "private-test-marker", "config.example.php": "private-test-marker",
                          "README.md": "private-test-marker", ".env": "private-test-marker",
                          "sovi.php.bak": "private-test-marker", "config.php~": "private-test-marker",
                          "unlisted.txt": "private-test-marker", "tests/index.php": "private-test-marker",
                          "tests/check.php": "private-test-marker"}.items():
        (api / name).write_text(content)
    config = private / "httpd.conf"
    loads = []
    for name in ["mpm_prefork", "unixd", "authz_core", "dir", "rewrite", "headers"]:
        path = modules / f"mod_{name}.so"
        if path.exists():
            loads.append(f'LoadModule {name}_module "{path}"')
    config.write_text("\n".join([
        f'ServerRoot "{private}"', f'PidFile "{private / "httpd.pid"}"',
        f'Listen 127.0.0.1:{port}', f'ServerName 127.0.0.1:{port}',
        *loads, f'User {getpass.getuser()}', f'Group {grp.getgrgid(os.getgid()).gr_name}',
        f'ErrorLog "{private / "error.log"}"', f'Mutex file:{private} default',
        'ServerTokens Prod', 'ServerSignature Off', f'DocumentRoot "{web}"',
        '<Directory />', 'Require all denied', '</Directory>',
        f'<Directory "{web}">', 'Options FollowSymLinks', 'AllowOverride All',
        'Require all granted', '</Directory>',
    ]) + "\n")
    subprocess.run([httpd, "-t", "-f", str(config)], check=True)
    with tempfile.TemporaryFile() as server_log:
        process = subprocess.Popen([httpd, "-X", "-f", str(config)], stdout=server_log, stderr=server_log)

        def request(path="", method="GET", data=None):
            req = urllib.request.Request(f"http://127.0.0.1:{port}/sovi-api/" + path,
                                         method=method, data=data)
            try:
                response = urllib.request.urlopen(req, timeout=2)
            except urllib.error.HTTPError as error:
                response = error
            with response:
                return response.status, response.headers, response.read()

        try:
            for _ in range(50):
                try:
                    status, headers, body = request()
                    break
                except urllib.error.URLError:
                    if process.poll() is not None:
                        raise RuntimeError("Private Apache could not start")
                    time.sleep(0.05)
            else:
                raise RuntimeError("Private Apache did not become ready")
            assert status == 200 and body == b"entrypoint", (status, body)
            assert headers["X-Frame-Options"] == "DENY"
            assert headers["X-Content-Type-Options"] == "nosniff"
            assert "default-src 'none'" in headers["Content-Security-Policy"]
            assert "no-store" in headers["Cache-Control"]
            checks = 5
            for path in ["index.php", "sovi.php", "index.php?action=health"]:
                assert request(path)[0] == 200, path
                checks += 1
            for path in ["config.php", "config.example.php", "README.md", ".env", ".htaccess", ".git/config",
                         "sovi.php.bak", "config.php~", "unlisted.txt", "INDEX.PHP", "tests/",
                         "tests/check.php", "tests/index.php", "index.php/extra", "sovi.php/extra",
                         "%63onfig.php", "config.php?action=health", "sovi.local.php"]:
                status, _, body = request(path)
                assert status in (403, 404) and b"private-test-marker" not in body, (path, status, body)
                checks += 1
            # TRACE is handled by Apache before per-directory access rules and
            # requires host-level TraceEnable Off, not an .htaccess directive.
            for method in ["PUT", "DELETE", "PATCH", "HEAD"]:
                method_status = request("index.php", method)[0]
                assert method_status == 403, (method, method_status)
                checks += 1
            for method in ["POST", "OPTIONS"]:
                # Static fixtures can return 200/405, but the allowlist must not
                # forbid these methods needed by the real PHP endpoint.
                assert request("index.php", method)[0] in (200, 405), method
                checks += 1
            assert request("index.php", "POST", b"x" * 32769)[0] == 413
            checks += 1
            print(f"Apache access checks passed: {checks} (harmless static fixtures)")
        except Exception:
            log = private / "error.log"
            if log.exists():
                print(log.read_text()[-5000:])
            raise
        finally:
            process.terminate()
            process.wait(timeout=5)
