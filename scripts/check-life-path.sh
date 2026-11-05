#!/bin/bash
set -euo pipefail
SOVI_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SOVI_CHECK_DIR="$SOVI_ROOT/artifacts/life-path-check"
mkdir -p "$SOVI_CHECK_DIR"
python3 - "$SOVI_ROOT" "$SOVI_CHECK_DIR" <<'PY'
from pathlib import Path
import plistlib, shutil, sys
root, output = map(Path, sys.argv[1:])
bundle = output / 'Fixtures.bundle/Contents'
fixtures = bundle / 'Resources/Fixtures'
fixtures.mkdir(parents=True, exist_ok=True)
for name in ['life-path-33.json', 'life-path-33.txt', 'vaccination-pass-2026.json', 'vaccination-pass-2026.txt', 'vaccination-pass-2026.pdf']:
    shutil.copyfile(root / 'apps/ios/Sovi/Resources/Fixtures' / name, fixtures / name)
(bundle / 'Info.plist').write_bytes(plistlib.dumps({'CFBundleIdentifier': 'at.sovi.validation.fixtures', 'CFBundlePackageType': 'BNDL', 'CFBundleName': 'Fixtures'}))
files = ['apps/ios/Sovi/Core/CasePreparation.swift', 'apps/ios/Sovi/Core/PrototypeProfile.swift', 'apps/ios/Sovi/Core/DemoScenarios.swift', 'apps/ios/Sovi/Core/Domain.swift', 'apps/ios/Sovi/Core/LifePath.swift', 'apps/ios/Sovi/Core/VaccinationPass.swift', 'apps/ios/Sovi/Core/PathCompanionPrompt.swift', 'apps/ios/Sovi/Services/CompanionService.swift', 'scripts/check-life-path.swift']
(output / 'validate.swift').write_text('\n'.join((root / name).read_text() for name in files))
PY
swift -module-cache-path "$SOVI_ROOT/artifacts/SwiftModuleCache" "$SOVI_CHECK_DIR/validate.swift" "$SOVI_CHECK_DIR/Fixtures.bundle"
