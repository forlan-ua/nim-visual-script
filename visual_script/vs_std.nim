import json, variant
import vs_host


type LitVSHost* = ref object of VSHost
method setValue*(host: LitVSHost, val: string) {.base.} = discard


type StringLitVSHost* = ref object of LitVSHost
    o0*: VSPort[string]

proc newStringLitVSHost*(): StringLitVSHost =
    result.new()
    result.name = "stringLit"
    result.flow = @[]
    result.o0 = newVSPort("output", string, VSPortKind.Output)

method setValue*(host: StringLitVSHost, val: string) = host.o0.write(val)

method getPort*(vs: StringLitVSHost; name: string, clone: bool = false, cloneAs: VSPortKind = VSPortKind.Output): Variant =
  if name == "o0":
    return newVariant(if clone: vs.o0.clone(cloneAs) else: vs.o0)

method connect*(vs: StringLitVSHost; port: string; port2: Variant) =
    if port == "o0":
      vs.o0.connect(port2)

method metadata*(vs: StringLitVSHost): VSHostMeta =
  return ("StringLitVSHost", "StringLiteral", @[], @[("output", "string", "")])

putHostToRegistry(StringLitVSHost, proc(): VSHost = newStringLitVSHost())


type IntLitVSHost* = ref object of LitVSHost
    o0*: VSPort[int]

proc newIntLitVSHost*(): IntLitVSHost =
    result.new()
    result.name = "intLit"
    result.flow = @[]
    result.o0 = newVSPort("output", int, VSPortKind.Output)

method setValue*(host: IntLitVSHost, val: string) = host.o0.write(parseInt(val))

method getPort*(vs: IntLitVSHost; name: string, clone: bool = false, cloneAs: VSPortKind = VSPortKind.Output): Variant =
  if name == "o0":
    return newVariant(if clone: vs.o0.clone(cloneAs) else: vs.o0)

method connect*(vs: IntLitVSHost; port: string; port2: Variant) =
    if port == "o0":
        vs.o0.connect(port2)

method metadata*(vs: IntLitVSHost): VSHostMeta =
    return ("IntLitVSHost", "IntLiteral", @[], @[("output", "int", "")])

putHostToRegistry(IntLitVSHost, proc(): VSHost = newIntLitVSHost())


type FloatLitVSHost* = ref object of LitVSHost
    o0*: VSPort[float]

proc newFloatLitVSHost*(): FloatLitVSHost =
    result.new()
    result.name = "floatLit"
    result.flow = @[]
    result.o0 = newVSPort("output", float, VSPortKind.Output)

method setValue*(host: FloatLitVSHost, val: string) = host.o0.write(parseFloat(val))

method getPort*(vs: FloatLitVSHost; name: string, clone: bool = false, cloneAs: VSPortKind = VSPortKind.Output): Variant =
  if name == "o0":
    return newVariant(if clone: vs.o0.clone(cloneAs) else: vs.o0)

method connect*(vs: FloatLitVSHost; port: string; port2: Variant) =
    if port == "o0":
        vs.o0.connect(port2)

method metadata*(vs: FloatLitVSHost): VSHostMeta =
    return ("FloatLitVSHost", "FloatLiteral", @[], @[("output", "float", "")])

putHostToRegistry(FloatLitVSHost, proc(): VSHost = newFloatLitVSHost())


type BoolLitVSHost* = ref object of LitVSHost
    o0*: VSPort[bool]

proc newBoolLitVSHost*(): BoolLitVSHost =
    result.new()
    result.name = "boolLit"
    result.flow = @[]
    result.o0 = newVSPort("output", bool, VSPortKind.Output)

method setValue*(host: BoolLitVSHost, val: string) = host.o0.write(val == "1")

method getPort*(vs: BoolLitVSHost; name: string, clone: bool = false, cloneAs: VSPortKind = VSPortKind.Output): Variant =
  if name == "o0":
    return newVariant(if clone: vs.o0.clone(cloneAs) else: vs.o0)

method connect*(vs: BoolLitVSHost; port: string; port2: Variant) =
    if port == "o0":
        vs.o0.connect(port2)

method metadata*(vs: BoolLitVSHost): VSHostMeta =
    return ("BoolLitVSHost", "BoolLiteral", @[], @[("output", "bool", "")])

putHostToRegistry(BoolLitVSHost, proc(): VSHost = newBoolLitVSHost())


type JsonLitVSHost* = ref object of LitVSHost
    o0*: VSPort[JsonNode]

proc newJsonLitVSHost*(): JsonLitVSHost =
    result.new()
    result.name = "jsonLit"
    result.flow = @[]
    result.o0 = newVSPort("output", JsonNode, VSPortKind.Output)

method setValue*(host: JsonLitVSHost, val: string) = host.o0.write(val.parseJson())

method getPort*(vs: JsonLitVSHost; name: string, clone: bool = false, cloneAs: VSPortKind = VSPortKind.Output): Variant =
  if name == "o0":
    return newVariant(if clone: vs.o0.clone(cloneAs) else: vs.o0)

method connect*(vs: JsonLitVSHost; port: string; port2: Variant) =
    if port == "o0":
        vs.o0.connect(port2)

method metadata*(vs: JsonLitVSHost): VSHostMeta =
    return ("JsonLitVSHost", "JsonLiteral", @[], @[("output", "JsonNode", "")])

putHostToRegistry(JsonLitVSHost, proc(): VSHost = newJsonLitVSHost())


type IfVSHost* = ref object of VSHost
    i0*: VSPort[bool]
    falseFlow*: seq[VSHost]

proc newIfVSHost*(): IfVSHost =
    result.new()
    result.name = "if"
    result.flow = @[]
    result.falseFlow = @[]
    result.i0 = newVSPort("condition", bool, VSPortKind.Input)

method invokeFlow*(host: IfVSHost) =
    if host.i0.read():
        for h in host.flow:
            h.invokeFlow()
    else:
        for h in host.falseFlow:
            h.invokeFlow()

method getPort*(vs: IfVSHost; name: string, clone: bool = false, cloneAs: VSPortKind = VSPortKind.Output): Variant =
    if name == "i0":
        return newVariant(if clone: vs.i0.clone(cloneAs) else: vs.i0)

method connect*(vs: IfVSHost; port: string; port2: Variant) =
    if port == "i0":
        vs.i0.connect(port2)

method metadata*(vs: IfVSHost): VSHostMeta =
    return ("IfVSHost", "IfVSHost", @[("condition", "bool", "")], @[("false", "VSFlow", "")])

putHostToRegistry(IfVSHost, proc(): VSHost = newIfVSHost())


type IfElifVSHost* = ref object of VSHost
    ports*: seq[VSPort[bool]]
    trueFlow*: seq[seq[VSHost]]
    falseFlow*: seq[VSHost]

proc newIfElifVSHost*(): IfElifVSHost =
    result.new()
    result.name = "if"
    result.trueFlow = @[]
    result.falseFlow = @[]
    result.ports = @[]

method invokeFlow*(vs: IfElifVSHost) =
    for i, b in vs.ports:
        if b.read():
            for h in vs.trueFlow[i]:
                h.invokeFlow()
                return

    for h in vs.falseFlow:
        h.invokeFlow()

proc setLen*(vs: IfElifVSHost, len: Natural) =
    if vs.ports.len > len:
        vs.ports.setLen(len)
        vs.trueFlow.setLen(len)
    else:
        let oldLen = vs.ports.len
        for i in oldLen ..< len:
            vs.ports.add(newVSPort("condition" & $i, bool, VSPortKind.Input))
            vs.trueFlow.add(newSeq[VSHost]())

proc port*(vs: IfElifVSHost, ind: Natural): VSPort[bool] =
    vs.ports[ind]

putHostToRegistry(IfElifVSHost, proc(): VSHost = newIfElifVSHost())


type WhileVSHost* = ref object of VSHost
    i0*: VSPort[bool]
    endFlow*: seq[VSHost]

proc newWhileVSHost*(): WhileVSHost =
    result.new()
    result.name = "while"
    result.flow = @[]
    result.endFlow = @[]
    result.i0 = newVSPort("condition", bool, VSPortKind.Input)

method invokeFlow*(host: WhileVSHost) =
    while host.i0.read():
        for h in host.flow:
            h.invokeFlow()
    for h in host.endFlow:
        h.invokeFlow()

putHostToRegistry(WhileVSHost, proc(): VSHost = newWhileVSHost())

proc iadd(i1, i2: int): int {.vshost.} = i1 + i2

proc eqString*(str1, str2: string): bool {.vshost.} =
    result = str1 == str2


# type PrintVSHost* = ref object of LitVSHost
#     i0*: VSPort[string]

# proc newPrintVSHost*(): PrintVSHost =
#     result.new()
#     result.name = "Print"
#     result.flow = @[]
#     # result.o0 = newVSPort("output", string, VSPortKind.Output)

# # method setValue*(host: PrintVSHost, val: string) = host.o0.write(val.parseJson())

# # method getPort*(vs: PrintVSHost; name: string, clone: bool = false, cloneAs: VSPortKind = VSPortKind.Output): Variant =
# #   if name == "o0":
# #     return newVariant(if clone: vs.o0.clone(cloneAs) else: vs.o0)

# # method connect*(vs: PrintVSHost; port: string; port2: Variant) =
# #     if port == "o0":
# #         vs.o0.connect(port2)

# method metadata*(vs: PrintVSHost): VSHostMeta =
#     return ("PrintVSHost", "Printeral", @[], @[("output", "any", "")])

# putHostToRegistry(PrintVSHost, proc(): VSHost = newJsonLitVSHost())

proc print*(args: seq[string]) {.vshost.} =
    # echo args.join(" ")
    echo "vsprint: ", args

proc print*(arg: int) {.vshost.} =
    echo "vsprint: ", arg


proc portConverter*[I, O](p: VSPort[I]): O =
    discard

