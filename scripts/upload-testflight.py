#!/usr/bin/env python3
"""Upload an exported macOS package using an injected App Store Connect API key."""

import argparse
import json
import os
from pathlib import Path
import re
import subprocess
import sys
import tempfile


def fail(message: str) -> None:
    print(message, file=sys.stderr)
    raise SystemExit(1)


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("package", type=Path, help="Exported, signed .pkg to upload")
    parser.add_argument("--wait", action="store_true", help="Wait for Apple processing")
    args = parser.parse_args()
    package = args.package.expanduser().resolve()
    if package.suffix.lower() != ".pkg" or not package.is_file():
        fail("Choose an existing exported .pkg file.")

    key_id = os.environ.get("ASC_KEY_ID", "")
    issuer = os.environ.get("ASC_ISSUER_ID", "")
    private_key = os.environ.get("ASC_PRIVATE_KEY", "").replace("\\n", "\n").strip()
    if not re.fullmatch(r"[A-Z0-9]{10}", key_id):
        fail("Inject ASC_KEY_ID from the credential manager.")
    if not re.fullmatch(r"[a-fA-F0-9]{8}-(?:[a-fA-F0-9]{4}-){3}[a-fA-F0-9]{12}", issuer):
        fail("Inject ASC_ISSUER_ID from the credential manager.")
    if not (private_key.startswith("-----BEGIN PRIVATE KEY-----") and
            private_key.endswith("-----END PRIVATE KEY-----")):
        fail("Inject the PEM ASC_PRIVATE_KEY from the credential manager.")

    os.umask(0o077)
    repository = Path(__file__).resolve().parents[1]
    private_root = repository / "_local"
    private_root.mkdir(mode=0o700, exist_ok=True)
    if private_root.is_symlink():
        fail("The private output directory must not be a symbolic link.")
    log_descriptor, log_name = tempfile.mkstemp(prefix="upload-", suffix=".log", dir=private_root)
    log_path = Path(log_name)

    with os.fdopen(log_descriptor, "wb") as log:
        with tempfile.TemporaryDirectory(prefix="asc-key-", dir=private_root) as temporary:
            key_path = Path(temporary) / f"AuthKey_{key_id}.p8"
            key_path.write_text(private_key + "\n", encoding="utf-8")
            # The upload tool only needs the selected key file and identifiers, not injected secrets.
            secret_prefixes = ("MEMOS_", "ASC_", "APPLE_", "INFISICAL_")
            environment = {
                name: value for name, value in os.environ.items()
                if not name.startswith(secret_prefixes)
            }
            command = ["xcrun", "altool", "--upload-package", str(package),
                       "--api-key", key_id, "--api-issuer", issuer,
                       "--p8-file-path", str(key_path), "--output-format", "json"]
            if args.wait:
                command.append("--wait")
            try:
                result = subprocess.run(command, env=environment, stdout=log,
                                        stderr=subprocess.STDOUT, check=False)
            except OSError:
                fail(f"Upload tool could not start. Inspect {log_path} privately.")

    if result.returncode:
        fail(f"Upload did not confirm success. Inspect {log_path} privately and check App Store Connect before retrying.")
    print(json.dumps({"uploaded": True, "waitedForProcessing": args.wait,
                      "log": str(log_path), "package": str(package)}))
    print("Confirm the processed build and internal TestFlight availability in App Store Connect.")


if __name__ == "__main__":
    main()
