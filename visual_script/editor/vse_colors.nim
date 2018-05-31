import nimx.types
import tables
import vse_types

colorTable["string"] = newColor(0.1, 0.45, 0.76, 1.0)
colorTable["int"] = newColor(0.9, 0.45, 0.26, 1.0)
colorTable["float"] = newColor(0.14, 0.45, 0.76, 1.0)
colorTable["char"] = newColor(0.5, 0.45, 0.76, 1.0)
colorTable["bool"] = newColor(0.55, 0.95, 0.76, 1.0)

proc colorForType*(typ: string): Color =
    result = colorTable.getOrDefault(typ)
    if result.a <= 0.1:
        result = whiteColor()


