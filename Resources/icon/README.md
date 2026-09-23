# Icon

`render.swift` draws the Snipbook icon with Core Graphics paths (no fonts or SF Symbols), using the One Dark syntax palette from the editor. The app uses the `1-midnight` concept; the other concepts are kept in the script for reference.

Regenerate `Resources/AppIcon.icns` from this folder:

```bash
swift render.swift --iconset 1-midnight /tmp/AppIcon.iconset
iconutil -c icns /tmp/AppIcon.iconset -o ../AppIcon.icns
```
