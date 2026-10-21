# MiniThermal 图标

## v1.0.3–v1.0.4 当前扁平图标

纯青绿色圆角底、白色四叶风扇、中心橙色圆点；无渐变、投影或立体纹理。应用列表与 Finder 使用此图标，插件面板恢复最初的青绿色系统风扇符号，顶部菜单栏保留单色风扇符号。

本版采用原生矢量绘制，不调用图像生成服务。可编辑源图为 `Assets/AppIcon.svg`；`scripts/render-flat-icon.swift` 生成 1024×1024 PNG 与 SVG，`scripts/build-icons.sh` 生成 macOS 的 10 种图标尺寸。v1.0.4 通过 actool 编译资源目录，生成 Assets.car、MiniThermalIcon.icns 与对应的应用图标声明。构建不依赖网络，保留透明外边距。

## v1.0.1 历史设计（已替换）

视觉：青绿色圆角底、白色三叶风扇、橙红色温度计。风扇是主视觉，温度计补充温度监测含义；透明外边距用于 macOS 图标排版。

生成方式：Codex 内置 imagegen 工具，透明背景。生成的原图保存在 `Assets/AppIcon.png`。构建时仅通过 macOS sips 缩放为系统要求的 10 种尺寸，并使用 iconutil 打包为 AppIcon.icns；保留透明度。

应用图标与面板标题使用同一图像。菜单栏使用系统单色风扇符号，适配浅色与深色菜单栏。

## 完整生成提示词

Use case: logo-brand. Asset type: production macOS application icon for MiniThermal, a Mac mini fan-control and temperature-monitoring utility. Create exactly one finished square app icon, 1024x1024. A confident white three-blade fan with a circular hub is the dominant symbol; incorporate a small, clean thermometer with a warm coral-orange bulb and column into the lower-right of the fan composition to convey temperature monitoring. Center the symbols inside a rich deep-teal rounded-square app tile, with a very restrained turquoise-to-teal gradient, subtle softly sculpted native macOS material and crisp silhouettes. Calm, precise, contemporary, premium desktop utility, legible at small icon sizes. The tile is front-facing and centered, approximately 824x824 pixels inside the 1024x1024 canvas, leaving transparent margins of about 100 pixels on each side. The entire area outside the rounded-square tile must be genuinely transparent. Keep the main fan visually balanced and large, with minimal shading, no busy detail. No text, no letters, no numerals, no captions, no mockup, no desktop, no border around the image, no watermark. Deliver a single standalone icon, not an icon sheet.

注：工具实际返回 1254×1254 PNG；构建脚本自动生成最大 1024×1024 的 macOS 图标表示。
