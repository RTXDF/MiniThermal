#!/bin/zsh
set -eu
project_dir="${0:A:h:h}"
cd "$project_dir"
mkdir -p build/MiniThermal.app/Contents/MacOS build/MiniThermal.app/Contents/Resources
touch build/.metadata_never_index
zsh scripts/build-icons.sh
xcrun clang -Wall -Wextra -Werror -O2 -mmacosx-version-min=14.0 -c Sources/ThermalSMC.c -o build/ThermalSMC.o
xcrun clang -Wall -Wextra -Werror -O2 -mmacosx-version-min=14.0 Sources/helper.c build/ThermalSMC.o -framework IOKit -framework CoreFoundation -o build/MiniThermal.app/Contents/MacOS/MiniThermalHelper
xcrun swiftc -swift-version 5 -O -parse-as-library -target arm64-apple-macosx14.0 -import-objc-header Sources/ThermalSMC.h Sources/InstanceLock.swift Sources/Monitor.swift Sources/Panel.swift Sources/App.swift build/ThermalSMC.o -framework AppKit -framework SwiftUI -framework ServiceManagement -framework IOKit -o build/MiniThermal.app/Contents/MacOS/MiniThermal
python3 - <<'PY'
import plistlib
with open('Info.plist', 'rb') as source:
    info = plistlib.load(source)
with open('build/icon-info.plist', 'rb') as generated:
    info.update(plistlib.load(generated))
with open('build/MiniThermal.app/Contents/Info.plist', 'wb') as output:
    plistlib.dump(info, output)
PY
cp References/Stats-LICENSE build/MiniThermal.app/Contents/Resources/Stats-LICENSE
cp build/IconResources/Assets.car build/MiniThermal.app/Contents/Resources/Assets.car
cp build/IconResources/MiniThermalIcon.icns build/MiniThermal.app/Contents/Resources/MiniThermalIcon.icns
cp Assets/AppIcon.png build/MiniThermal.app/Contents/Resources/AppIcon.png
codesign --force --sign - build/MiniThermal.app/Contents/MacOS/MiniThermalHelper
codesign --force --sign - build/MiniThermal.app
xcrun swift scripts/check-app-icon.swift "$project_dir/build/MiniThermal.app"
touch build/MiniThermal.app
print "已生成 $project_dir/build/MiniThermal.app"
