#!/bin/zsh
set -eu
project_dir="${0:A:h:h}"
cd "$project_dir"
source_icon="Assets/AppIcon.png"
mkdir -p Assets
xcrun swift scripts/render-flat-icon.swift "$source_icon" Assets/AppIcon.svg
mkdir -p build/AppIcon.iconset
for logical_size in 16 32 128 256 512; do
    sips -z "$logical_size" "$logical_size" "$source_icon" --out "build/AppIcon.iconset/icon_${logical_size}x${logical_size}.png" >/dev/null
    retina_size=$((logical_size * 2))
    sips -z "$retina_size" "$retina_size" "$source_icon" --out "build/AppIcon.iconset/icon_${logical_size}x${logical_size}@2x.png" >/dev/null
done
iconutil --convert icns build/AppIcon.iconset --output build/AppIcon.icns
python3 - <<'PY'
from pathlib import Path
import json, shutil
catalog = Path('build/AppAssets.xcassets')
icons = catalog / 'MiniThermalIcon.appiconset'
icons.mkdir(parents=True, exist_ok=True)
(catalog / 'Contents.json').write_text(json.dumps({'info': {'author': 'xcode', 'version': 1}}))
images = []
for size in [16, 32, 128, 256, 512]:
    for scale in [1, 2]:
        name = f'icon_{size}x{size}' + ('@2x' if scale == 2 else '') + '.png'
        shutil.copy2(Path('build/AppIcon.iconset') / name, icons / name)
        images.append({'filename': name, 'idiom': 'mac', 'scale': f'{scale}x', 'size': f'{size}x{size}'})
(icons / 'Contents.json').write_text(json.dumps({'images': images, 'info': {'author': 'xcode', 'version': 1}}, indent=2))
Path('build/IconResources').mkdir(exist_ok=True)
PY
xcrun actool build/AppAssets.xcassets --compile build/IconResources --platform macosx --minimum-deployment-target 14.0 --app-icon MiniThermalIcon --output-partial-info-plist build/icon-info.plist --output-format human-readable-text --notices --warnings
