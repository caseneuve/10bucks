#!/usr/bin/env python3
"""One bounded run on an already running coordinator-owned debug guest.

Coordinator only: invoke warm three times and cold five times; stop on failure.
No VM lifecycle, builds, settings, stress sender, or functional controller.
"""
import argparse
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import shutil
import subprocess
import time
import uuid

ROOT = Path(__file__).resolve().parents[2] # benchmarks -> functional-tests -> repository


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--vm', required=True)
    parser.add_argument('--mode', choices=('warm', 'cold'), required=True)
    args = parser.parse_args()
    if not args.vm.startswith('10bucks-run-ft-'):
        parser.error('requires coordinator-owned FT debug guest')
    owner_dir = ROOT / 'vm/results' / args.vm
    owner = json.loads((owner_dir / 'debug-owner.json').read_text())
    if owner.get('vm') != args.vm:
        parser.error('ownership mismatch')
    nonce = uuid.uuid4().hex
    results = owner_dir / ('chooser-' + nonce[:12])
    source = results / 'source'
    results.mkdir(parents=True)
    # Freeze prebuilt artifacts only. Coordinator prepares/builds before invocation.
    shutil.copytree(ROOT / '10bucks.spoon', source / '10bucks.spoon')
    for name in ('benchmarks', 'fixture'):
        shutil.copytree(ROOT / 'functional-tests' / name, source / 'functional-tests' / name,
                        ignore=shutil.ignore_patterns('build', '__pycache__'))
    shutil.copytree(ROOT / 'functional-tests/fixture/build/Fixture.app', source / 'Fixture.app')
    shutil.copytree(ROOT / 'vm', source / 'vm', ignore=shutil.ignore_patterns('results'))
    manifest = {str(p.relative_to(source)): hashlib.sha256(p.read_bytes()).hexdigest()
                for p in sorted(source.rglob('*')) if p.is_file()}
    if not any('.so' in name or '.dylib' in name for name in manifest):
        raise RuntimeError('prebuilt native binary missing')
    (results / 'manifest.json').write_text(json.dumps(manifest, indent=2) + '\n')
    spec = importlib.util.spec_from_file_location('frozen_chooser', source / 'functional-tests/benchmarks/chooser.py')
    oracle = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(oracle)
    env = dict(os.environ, TENBUCKS_VM=args.vm, TENBUCKS_VM_OWNER_ROOT=str(ROOT / 'vm/results'))
    guest_out = '/Volumes/My Shared Files/results/' + results.name
    guest_source = guest_out + '/source'
    deadline = time.monotonic() + 85

    def ipc(code):
        left = deadline - time.monotonic()
        if left <= 0:
            raise RuntimeError('runner deadline')
        r = subprocess.run([str(source / 'vm/hs'), code], env=env, text=True,
                           capture_output=True, timeout=min(10, left))
        with (results / 'ipc.jsonl').open('a') as f:
            f.write(json.dumps(dict(at=time.time(), code=code, stdout=r.stdout, stderr=r.stderr, returncode=r.returncode)) + '\n')
        r.check_returncode()
        return json.loads(r.stdout.strip().splitlines()[-1])

    def read_raw():
        try:
            return json.loads((results / 'chooser-raw.json').read_text())
        except (FileNotFoundError, json.JSONDecodeError):
            return None

    error = None
    owned = False
    try:
        # Never take over another observer/candidate. Runtime fresh for each run.
        preflight = ipc('return hs.json.encode({busy=(ft and ft.status and ft.status().running) or (chooserBench and chooserBench.status().running) or false})')
        if preflight['busy']:
            raise RuntimeError('guest observer busy')
        options = dict(sourceRoot=guest_source, outputDir=guest_out, controlDir=guest_out + '/control',
                       executable=guest_source + '/Fixture.app/Contents/MacOS/Fixture', run=nonce, mode=args.mode)
        lua_options = '{' + ','.join(k + '=' + json.dumps(v) for k, v in options.items()) + '}'
        owned = True # busy preflight passed; only this invocation may be stopped
        ipc('for name in pairs(package.loaded) do if name:match("^lib%.") then package.loaded[name]=nil end end; chooserBench=dofile(' + json.dumps(guest_source + '/functional-tests/benchmarks/chooser_guest.lua') + '); return hs.json.encode(chooserBench.start(' + lua_options + '))')
        while time.monotonic() < deadline - 12:
            raw = read_raw()
            if raw and raw.get('cleanup'):
                break
            time.sleep(.1)
        else:
            raise RuntimeError('missing bounded guest result')
        summary = oracle.validate_batch(raw, args.mode)
        # Verify executed snapshot unchanged after execution.
        for name, digest in manifest.items():
            if hashlib.sha256((source / name).read_bytes()).hexdigest() != digest:
                raise RuntimeError('frozen artifact changed: ' + name)
        (results / 'chooser-summary.json').write_text(json.dumps(dict(run=nonce, mode=args.mode,
            definition=oracle.DEFINITION, summary=summary, acceptance=True), indent=2) + '\n')
    except Exception as exc:
        error = str(exc)
        try:
            if not owned:
                raise RuntimeError('no observer owned; existing guest untouched')
            ipc('if chooserBench and chooserBench.status().run==' + json.dumps(nonce) + ' and chooserBench.status().running then chooserBench.stop() end; return hs.json.encode({stopSubmitted=true})')
            until = min(deadline, time.monotonic() + 7)
            while time.monotonic() < until:
                raw = read_raw()
                if raw and raw.get('cleanup'):
                    break
                time.sleep(.1)
        except Exception as cleanup_exc:
            error += '; cleanup transport: ' + str(cleanup_exc)
        (results / 'chooser-summary.json').write_text(json.dumps(dict(run=nonce, mode=args.mode,
            acceptance=False, error=error, cleanup=(read_raw() or {}).get('cleanup')), indent=2) + '\n')
    print(results)
    if error:
        raise SystemExit(error)


if __name__ == '__main__':
    main()
