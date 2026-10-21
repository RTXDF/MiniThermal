import AppKit

guard CommandLine.arguments.count == 2,
      let bundle = Bundle(path: CommandLine.arguments[1]),
      let name = bundle.object(forInfoDictionaryKey: "CFBundleIconName") as? String else {
    fputs("FAIL: app does not declare an asset-catalog icon name\n", stderr)
    exit(1)
}
guard bundle.url(forResource: "Assets", withExtension: "car") != nil else {
    fputs("FAIL: compiled icon catalog is missing\n", stderr)
    exit(1)
}
guard let image = bundle.image(forResource: NSImage.Name(name)), image.isValid else {
    fputs("FAIL: declared app icon cannot be loaded from the catalog\n", stderr)
    exit(1)
}
print("PASS: asset-catalog icon \(name) loads from the app bundle (\(Int(image.size.width))×\(Int(image.size.height)))")
