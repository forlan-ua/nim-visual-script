import json, variant, random
import vs_host, vs_literal, vs_network, vs_flow_extensions



genLiteralVSHost(int, parseInt)
genLiteralVSHost(bool, parseBool)
genLiteralVSHost(float, parseFloat)
genLiteralVSHost(string)
genLiteralVSHost(JsonNode, parseJson)


proc iadd(i1, i2: int): int {.vshost.} = i1 + i2

proc eqString*(str1, str2: string): bool {.vshost.} =
    result = str1 == str2

proc print*(args: seq[string]) {.vshost.} =
    echo "vsprint: ", args

proc print*(arg: int) {.vshost.} =
    echo "vsprint: ", arg

proc print*(arg: string) {.vshost.} =
    echo "vsprint: ", arg

proc cmpint*(a, b: int): bool {.vshost.} = a == b

proc randomInt*(): int {.vshost.} =
    result = rand(high(int))
