#!/usr/bin/env python3
"""Typecheck the UIKit/SwiftUI app against a cross-compiled SwiftPM core.
Usage: python3 scripts/typecheck-ios.py /path/to/swiftpm-scratch [output-executable]
The full Xcode build remains the distribution gate.
"""
from pathlib import Path
import subprocess,sys,os
scratch=Path(sys.argv[1] if len(sys.argv)>1 else '.build-ios')
build=scratch/'arm64-apple-ios-simulator/debug'
sdk=subprocess.check_output(['xcrun','--sdk','iphonesimulator','--show-sdk-path'],text=True).strip()
cmd=['xcrun','swiftc','-typecheck','-parse-as-library','-disable-sandbox','-module-name','WoolooMobile','-swift-version','5','-target','arm64-apple-ios17.0-simulator','-sdk',sdk,'-I',str(build/'Modules'),'-module-cache-path',os.environ.get('CLANG_MODULE_CACHE_PATH','/private/tmp/wooloo-ui-cache')]
import re
maps = list(Path('Vendor').glob('*/Sources/*/include/module.modulemap')) + list(build.glob('*.build/module.modulemap')) + list((scratch/'checkouts').glob('*/Sources/*/include/module.modulemap'))
seen = set()
for file in maps:
    match = re.search(r'module\s+(\w+)', file.read_text())
    name = match.group(1) if match else str(file)
    if name not in seen:
        cmd += ['-Xcc','-fmodule-map-file='+str(file.resolve())]
        seen.add(name)
cmd += [str(f) for f in Path('WoolooMobile').glob('*.swift')]
if len(sys.argv) > 2:
    cmd[cmd.index('-typecheck')] = '-emit-executable'
    cmd += [str(p) for p in build.glob('*.build/**/*.o')]
    cmd += ['-o', sys.argv[2]]
sys.exit(subprocess.run(cmd).returncode)
