#!/bin/zsh
set -eu
project_dir="${0:A:h:h}"
cd "$project_dir"
mkdir -p build/MiniThermal.app/Contents/MacOS build/MiniThermal.app/Contents/Resources
zsh scripts/build-icons.sh
xcrun clang -Wall -Wextra -Werror -O2 -mmacosx-version-min=14.0 -c Sources/ThermalSMC.c -o build/ThermalSMC.o
xcrun clang -Wall -Wextra -Werror -O2 -mmacosx-version-min=14.0 Sources/helper.c build/ThermalSMC.o -framework IOKit -framework CoreFoundation -o build/MiniThermal.app/Contents/MacOS/MiniThermalHelper
xcrun swiftc -swift-version 5 -O -parse-as-library -target arm64-apple-macosx14.0 -import-objc-header Sources/ThermalSMC.h Sources/Monitor.swift Sources/Panel.swift Sources/App.swift build/ThermalSMC.o -framework AppKit -framework SwiftUI -framework ServiceManagement -framework IOKit -o build/MiniThermal.app/Contents/MacOS/MiniThermal
cp Info.plist build/MiniThermal.app/Contents/Info.plist
cp References/Stats-LICENSE build/MiniThermal.app/Contents/Resources/Stats-LICENSE
cp build/AppIcon.icns build/MiniThermal.app/Contents/Resources/AppIcon.icns
cp Assets/AppIcon.png build/MiniThermal.app/Contents/Resources/AppIcon.png
codesign --force --sign - build/MiniThermal.app/Contents/MacOS/MiniThermalHelper
codesign --force --sign - build/MiniThermal.app
print "已生成 $project_dir/build/MiniThermal.app"
