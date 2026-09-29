#!/usr/bin/env python3
"""Build and notarize the standalone CLI; publish only with --publish."""

import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import tempfile


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--publish', action='store_true', help='Create the CLI tag and GitHub release after notarization')
    parser.add_argument('--notes', type=Path, help='Release notes file, required to publish')
    args = parser.parse_args()
    root = Path(__file__).resolve().parents[1]
    os.chdir(root)
    os.umask(0o077)
    version = re.search(r'MARKETING_VERSION: "([0-9.]+)"', Path('project.yml').read_text())[1]
    tag = f'cli-v{version}'
    team = os.environ.get('APPLE_DEVELOPMENT_TEAM', '')
    key_id = os.environ.get('ASC_KEY_ID', '')
    issuer = os.environ.get('ASC_ISSUER_ID', '')
    if (not re.fullmatch(r'[A-Z0-9]{10}', team) or not re.fullmatch(r'[A-Z0-9]{10}', key_id)
            or not re.fullmatch(r'[a-fA-F0-9]{8}-(?:[a-fA-F0-9]{4}-){3}[a-fA-F0-9]{12}', issuer)):
        raise SystemExit('Inject APPLE_DEVELOPMENT_TEAM, ASC_KEY_ID and ASC_ISSUER_ID through the credential manager.')
    environment = {k: v for k, v in os.environ.items() if not k.startswith(('MEMOS_', 'PAD_', 'ASC_', 'APPLE_', 'INFISICAL_'))}
    output = root / 'releases' / tag
    if output.exists():
        raise SystemExit('Release output exists; inspect it before choosing a new version. Nothing was replaced.')
    output.mkdir(parents=True, mode=0o700)
    log = (output / 'release.log').open('wb')

    def run(command, capture=False):
        result = subprocess.run(command, env=environment, stdout=subprocess.PIPE if capture else log, stderr=log)
        if result.returncode:
            raise RuntimeError(f'{command[0]} failed; inspect {output / "release.log"} privately.')
        return result.stdout.decode().strip() if capture else None

    if args.publish:
        if not args.notes or not args.notes.is_file():
            raise SystemExit('--publish requires --notes FILE.')
        if run(['git', 'status', '--porcelain'], True) or run(['git', 'branch', '--show-current'], True) != 'main':
            raise SystemExit('Publish only from a clean main checkout.')
        run(['git', 'fetch', '--tags', 'origin', 'main'])
        if run(['git', 'rev-parse', 'HEAD'], True) != run(['git', 'rev-parse', 'origin/main'], True):
            raise SystemExit('main must match origin/main.')
        existing = subprocess.run(['git', 'rev-parse', '--verify', '--quiet', f'refs/tags/{tag}'], env=environment, capture_output=True)
        if existing.returncode == 0:
            raise SystemExit('The CLI tag already exists; do not overwrite a published release.')

    keychain = os.environ.get('MEMOS_SIGNING_KEYCHAIN')
    identities_command = ['security', 'find-identity', '-v', '-p', 'codesigning'] + ([keychain] if keychain else [])
    identities = run(identities_command, True)
    matches = re.findall(r'"(Developer ID Application: [^"\n]+\(' + re.escape(team) + r'\))"', identities)
    if not matches:
        raise SystemExit('No Developer ID Application certificate for the injected team in the selected keychain.')
    identity = matches[0]
    derived = output / 'DerivedData'
    run(['xcodebuild', '-quiet', '-project', 'Memos.xcodeproj', '-scheme', 'MemosTool', '-configuration', 'Release',
         '-destination', 'generic/platform=macOS', '-derivedDataPath', str(derived), 'ARCHS=arm64',
         'CODE_SIGNING_ALLOWED=NO', 'build'])
    staging = output / 'Memos-CLI'
    staging.mkdir(mode=0o755)
    binary = staging / 'memos'
    shutil.copyfile(derived / 'Build/Products/Release/memos', binary)
    binary.chmod(0o755)
    signing = ['codesign', '--force', '--options', 'runtime', '--timestamp', '--sign', identity]
    if keychain:
        signing += ['--keychain', keychain]
    run(signing + [str(binary)])
    run(['codesign', '--verify', '--strict', str(binary)])
    run(['python3', 'scripts/verify-cli.py', str(binary)])
    shutil.copyfile('LICENSE', staging / 'LICENSE')
    (staging / 'LICENSE').chmod(0o644)
    (staging / 'README.txt').write_text('Memos CLI for Apple silicon, macOS 27 or later.\n\n'
        'Install Memos from TestFlight or the App Store and open it once.\n'
        'Install this separate tool into a directory on your PATH, for example:\n'
        '  mkdir -p "$HOME/.local/bin"\n'
        '  install -m 755 memos "$HOME/.local/bin/memos"\n'
        'Run memos --help. The tool uses the same memo library as Memos.\n'
        'MEMOS_STORE can select a disposable library for testing.\n')
    (staging / 'README.txt').chmod(0o644)
    package = output / f'Memos-CLI-{version}-macos-arm64.zip'
    run(['ditto', '-c', '-k', '--keepParent', str(staging), str(package)])
    with tempfile.TemporaryDirectory(prefix='notary-key-', dir=output) as temporary:
        private_key = os.environ.get('ASC_PRIVATE_KEY', '').replace('\\n', '\n').strip()
        if private_key:
            key_path = Path(temporary) / 'AuthKey.p8'
            key_path.write_text(private_key + '\n')
        else:
            key_path = Path(os.environ.get('ASC_KEY_PATH', str(Path.home() / f'.appstoreconnect/private_keys/AuthKey_{key_id}.p8')))
        if not key_path.is_file():
            raise SystemExit('Inject ASC_PRIVATE_KEY or provide the existing source-rendered ASC_KEY_PATH.')
        auth = ['--key', str(key_path), '--key-id', key_id, '--issuer', issuer]
        result = json.loads(run(['xcrun', 'notarytool', 'submit', str(package), *auth, '--wait', '--output-format', 'json'], True))
        (output / 'notarization.json').write_text(json.dumps(result, indent=2) + '\n')
        if result.get('status') != 'Accepted':
            raise SystemExit('CLI notarization was not accepted. Inspect notarization.json privately; nothing published.')
    digest = hashlib.sha256(package.read_bytes()).hexdigest()
    checksum = output / 'SHA256SUMS'
    checksum.write_text(f'{digest}  {package.name}\n')
    if args.publish:
        run(['git', 'tag', '-a', tag, '-m', f'Memos CLI {version}'])
        run(['git', 'push', 'origin', tag])
        run(['gh', 'release', 'create', tag, str(package), str(checksum), '--verify-tag', '--title', f'Memos CLI {version}',
             '--notes-file', str(args.notes.resolve())])
        print(f'Published {tag}; verify the downloaded archive checksum and CLI behavior.')
    else:
        print(f'Notarized {package}. Nothing published.')


if __name__ == '__main__':
    main()
