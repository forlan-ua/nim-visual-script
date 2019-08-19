import vs_host, vs_network
import macros, strutils, variant, tables
export variant

type LitVSHost* = ref object of VSHost
method setValue*(host: LitVSHost, val: string) {.base.} = discard

registerPortNetworkExtension('=') do(net: VSNetwork, source: string, start: var int, hostId1, hostId2, port1Name, port2Name: var string, localHostMapper: Table[string, int]):
    assert(net.hosts[localHostMapper[hostId1]] of LitVSHost)

    start += source.parseUntil(port2Name, '\n', start + 1) + 2
    let host = net.hosts[localHostMapper[hostId1]]
    host.LitVSHost.setValue(port2Name)

proc typName(typ: NimNode): NimNode = ident(capitalizeAscii($typ)  & "LitVSHost")

proc genHostTyp(typ: NimNode): NimNode =
    let typName = typ.typName
    result = quote do:
        type `typName`* = ref object of LitVSHost
            o0*: VSPort[`typ`]

proc genMethods(typ: NimNode): NimNode =
    let typName = typ.typName
    let typNameLit = newLit($typ.typName)
    let typLit = newLit($typ)
    let typProcName = newLit(capitalizeAscii($typ) & "Literal")

    result = quote do:
        method getPort*(vs: `typName`, name: string, clone: bool = false, cloneAs: VSPortKind = VSPortKind.Output): Variant =
            if name == "o0":
                return newVariant(if clone: vs.o0.clone(cloneAs) else: vs.o0)

        method connect*(vs: `typName`; port: string; port2: Variant) =
            if port == "o0":
                vs.o0.connect(port2)

        method metadata*(vs: `typName`): VSHostMeta =
            return (`typNameLit`, `typProcName`, @[], @[("output", `typLit`, "")])

proc genCreatorAndPush(typ: NimNode): NimNode =
    let typName = typ.typName
    let nameLit = newLit(normalize($typ.typName))
    let procName = ident("create" & $typName)

    result = quote do:
        proc `procName`*(): VSHost =
            var r = new(`typName`)
            r.name = `nameLit`
            r.o0 = newVSPort("output", `typ`, VSPortKind.Output)
            r

        putHostToRegistry(`typName`, `procName`)

proc genSetValue(typ: NimNode, conv: NimNode): NimNode =
    let typName = typ.typName
    if conv.kind == nnkNilLit:
        result = quote do:
            method setValue*(vs: `typName`, val: string) = vs.o0.write(val)
    else:
        result = quote do:
            method setValue*(vs: `typName`, val: string) = vs.o0.write(`conv`(val))

## typ - typedesc
## conv - converter from string to `typ` # proc[T](v: string): T
macro genLiteralVSHost*(typ: typed, conv: untyped = nil): untyped =
    # echo "lit \n", treeRepr(typ)

    result = nnkStmtList.newTree()
    result.add(genHostTyp(typ))
    result.add(genMethods(typ))
    result.add(genSetValue(typ, conv))
    result.add(genCreatorAndPush(typ))

    # echo "repr \n", repr(result)
