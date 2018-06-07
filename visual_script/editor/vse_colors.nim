import nimx.types
import tables
import vse_types

proc color(r,g,b:int): Color = newColor(r / 255, g / 255, b / 255, 1.0)

const colors = @[
    color(165, 42, 42),
    color(220, 20, 60),
    color(255, 99, 71),
    color(255, 127, 80),
    color(233, 150, 122),
    color(255, 140, 0),
    color(255, 215, 0),
    color(218, 165, 32),
    color(238, 232, 170),
    color(128, 128, 0),
    color(154, 205, 50),
    color(34, 139, 34),
    color(144, 238, 144),
    color(143, 188, 143),
    color(0, 250, 154),
    color(32, 178, 170),
    color(47, 79, 79)
]

const unknownTypeColor = color(176,196,222)

proc addTypeToColorTable*(typ: string, c: Color)=
    colorTable[typ] = c

for i, typ in ["bool", "int", "int8", "int16", "int32", "string", "char", "float"]:
    addTypeToColorTable(typ, colors[i])

addTypeToColorTable(VSFLOWTYPE, flowColor)

proc colorForType*(typ: string): Color =
    result = colorTable.getOrDefault(typ)
    if result.a <= 0.1:
        result = unknownTypeColor


