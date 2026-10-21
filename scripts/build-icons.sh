#!/bin/zsh
set -eu
project_dir="${0:A:h:h}"
cd "$project_dir"
source_icon="Assets/AppIcon.png"
if [[ ! -f "$source_icon" ]]; then
    print -u2 "缺少应用图标：$source_icon"
    exit 1
fi
mkdir -p build/AppIcon.iconset
for logical_size in 16 32 128 256 512; do
    sips -z "$logical_size" "$logical_size" "$source_icon" --out "build/AppIcon.iconset/icon_${logical_size}x${logical_size}.png" >/dev/null
    retina_size=$((logical_size * 2))
    sips -z "$retina_size" "$retina_size" "$source_icon" --out "build/AppIcon.iconset/icon_${logical_size}x${logical_size}@2x.png" >/dev/null
done
iconutil --convert icns build/AppIcon.iconset --output build/AppIcon.icns
