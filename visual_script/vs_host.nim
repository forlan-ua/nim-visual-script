import macros, strutils, tables, strutils, typetraits, variant, parseutils
export strutils, tables, strutils, typetraits, variant, parseutils

type VSPortKind* {.pure.} = enum
    Input
    Output

type
    # PortDataConverter*[I, O] = ref object of RootObj
    #     dataConverter*: proc(p: VSPort[I]): O
    #     source*: VSPort[I]
    PortDataConverter*[I,O] = proc(p: VSPort[I]): O

    VSPort*[T] = ref object of RootObj
        name*: string
        data: T
        case kind*: VSPortKind:
            of Input:
                source: VSPort[T]
                hasData: bool
            of Output:
                readImpl*: proc(): T
        connections: seq[VSPort[T]]


proc connect*[T](p1, p2: VSPort[T]) =
    if p1.kind == VSPortKind.Input:
        assert(p2.kind == VSPortKind.Output)
        p1.source = p2
    else:
        assert(p2.kind == VSPortKind.Input)
        p2.source = p1

    let ind1 = p2.connections.find(p1)
    if ind1 == -1:
        p2.connections.add(p1)

    let ind2 = p1.connections.find(p2)
    if ind2 == -1:
        p1.connections.add(p2)


proc connect*[T](p1: VSPort[T], p2: Variant) =
    p1.connect(p2.get(p1.type))


proc disconnect*[T](p1, p2: VSPort[T]) =
    let ind1 = p2.connections.find(p1)
    if ind1 > -1:
        p2.connections.del(ind1)

    let ind2 = p1.connections.find(p2)
    if ind2 > -1:
        p1.connections.del(ind2)

    if p1.kind == VSPortKind.Input:
        assert(p2.kind == VSPortKind.Output)
        if p1.source == p2:
            if p1.connections.len > 0:
                p1.source = p1.connections[0]
            else:
                p1.source = nil
    else:
        assert(p2.kind == VSPortKind.Input)
        if p2.source == p1:
            if p2.connections.len > 0:
                p2.source = p2.connections[0]
            else:
                p2.source = nil


proc disconnect*(p: VSPort) =
    var ind = p.connections.high
    while ind > -1:
        p.disconnect(p.connections[ind])
        ind.dec


proc destroy*(p: VSPort) =
    p.disconnect()
    if p.kind == VSPortKind.Output:
        p.readImpl = nil


proc read*[T](vs: VSPort[T]): T =
    assert(vs.kind == VSPortKind.Input)
    if vs.hasData:
        return vs.data
    if not vs.source.isNil:
        return vs.source.readOutput()

proc write*[T](vs: VSPort[T], val: T) =
    vs.data = val
    if vs.kind == VSPortKind.Output:
        for connection in vs.connections:
            connection.source = vs
    else:
        vs.hasData = true


proc readOutput*[T](vs: VSPort[T]): T =
    assert(vs.kind == VSPortKind.Output)
    if not vs.readImpl.isNil:
        return vs.readImpl()
    else:
        return vs.data


proc rawData*[T](vs: VSPort[T]): T =
    assert(vs.kind == VSPortKind.Output)
    vs.data

proc newVSPort*(name: string, T: typedesc, kind: VSPortKind): VSPort[T] =
    result = VSPort[T](name: name, kind: kind)
    result.connections = @[]

proc clone*[T](port: VSPort[T], kind: VSPortKind): VSPort[T] =
    newVSPort(port.name, T, kind)


type VSHostMeta* = tuple[typeName, procName: string, inputs: seq[tuple[name, sign, default: string]], outputs: seq[tuple[name, sign, default: string]]]
type VSHost* = ref object of RootObj
    flow*: seq[VSHost]
    name*: string
    frozen: bool

method invoke*(vs: VSHost) {.base.} = discard
method metadata*(vs: VSHost): VSHostMeta {.base.} = discard
method getPort*(vs: VSHost, name: string, clone: bool = false, cloneAs: VSPortKind = VSPortKind.Output): Variant {.base.} = discard
method connect*(vs: VSHost, port: string, port2: Variant) {.base.} = discard
template connect*(vs: VSHost, port: string, vs2: VSHost, port2: string) = vs.connect(port, vs2.getPort(port2))
method destroy*(vs: VSHost) {.base.} = discard
method invokeFlow*(vs: VSHost) {.base.} =
    vs.frozen = true
    vs.invoke()
    for h in vs.flow:
        h.invokeFlow()

####
var hostRegistry = initTable[string, proc(): VSHost]()

proc putHostToRegistry*(T: string, creator: proc(): VSHost) =
    hostRegistry[T] = creator

proc putHostToRegistry*(T: typedesc[VSHost], creator: proc(): VSHost) =
    putHostToRegistry(T.name, creator)

proc getHostFromRegistry*(name: string): VSHost =
    if not hostRegistry.hasKey(name):
        raise newException(ValueError, "`" & name & "` has not been found in the registry.")
    hostRegistry[name]()

proc getHostFromRegistry*(T: typedesc[VSHost]): T =
    type TT = T
    return getHostFromRegistry[T](T.name).TT

iterator walkHostRegistry*(): VSHost =
    for host in hostRegistry.values():
        yield host()

####
var compileTimeRegistry {.compiletime.} = initTable[string, NimNode]()

proc getName(n: NimNode): string =
    if n.kind == nnkIdent:
        return $n
    elif n.kind == nnkAccQuoted:
        if n[1].eqIdent("="):
            return $n[0] & "Setter"
        else:
            return $n[0]
    elif n.kind == nnkPostfix:
        return $n[1]

proc createPortNode(name: NimNode, defType: NimNode): NimNode =
    result = newIdentDefs(
        nnkPostfix.newTree(
            ident("*"),
            name
        ),
        nnkBracketExpr.newTree(
            newIdentNode("VSPort"),
            defType
        )
    )

template createVSHostType(T, TT): untyped =
    type T* = ref object of TT

type InputPortNode = tuple[name, sign, default: NimNode]
type OutputPortNode = tuple[name, sign: NimNode]

proc generateOutputs(a: NimNode): seq[OutputPortNode] =
    let params = a[3]

    result = @[]

    if params[0].kind != nnkEmpty:
        if params[0].kind == nnkPar:
            for i in 0 ..< params[0].len:
                result.add((ident("output" & $i), params[0][i]))
        elif params[0].kind == nnkTupleTy:
            for i in 0 ..< params[0].len:
                let len = params[0][i].len
                for j in 0 ..< len - 2:
                    result.add((params[0][i][j], params[0][i][len - 2]))
        else:
            result.add((ident("output"), params[0]))

proc generateInputs(a: NimNode): seq[InputPortNode] =
    let params = a[3]

    result = @[]

    for i in 1 ..< params.len:
        let len = params[i].len
        for j in 0 ..< len - 2:
            result.add((params[i][j], params[i][len - 2], params[i][len - 1]))

proc generateTypeWithFields(a: NimNode, originalProcName: string, typeName: NimNode, outputs: seq[OutputPortNode], inputs: seq[InputPortNode]): NimNode =
    result = getAst(createVSHostType(typeName, ident("VSHost")))
    let recList = nnkRecList.newTree()
    result[0][2][0][2] = recList

    proc hostTypeHasArg(arg: NimNode): bool =
        for i in 0 ..< recList.len:
            if recList[i][0] == arg:
                return true

    for i, output in outputs:
        recList.add(createPortNode(ident("o" & $i), output.sign))

    for i, input in inputs:
        if hostTypeHasArg(input.name):
            error "Argument " & $input.name & " has been already setted for function " & originalProcName & ". Please check input and output arguments."
        recList.add(createPortNode(ident("i" & $i), input.sign))


proc generateOriginalFunctionCall(a: NimNode, inputs: seq[InputPortNode]): NimNode =
    var procName = a[0]
    if procName.kind == nnkPostfix:
        procName = procName[1]

    let invokeRes = nnkCall.newTree(
        procName
    )

    for i, input in inputs:
        invokeRes.add(
            nnkCall.newTree(
                nnkDotExpr.newTree(
                    nnkDotExpr.newTree(
                        ident("vs"),
                        ident("i" & $i)
                    ),
                    ident("read")
                )
            )
        )
    result = invokeRes

proc generateInvokeMethod(a: NimNode, typeName: NimNode, outputs: seq[OutputPortNode], inputs: seq[InputPortNode]): NimNode =
    let originalCall = generateOriginalFunctionCall(a, inputs)

    let invoke = newProc(
        nnkPostfix.newTree(ident("*"), ident("invoke")),
        [newEmptyNode(), nnkIdentDefs.newTree(ident("vs"), typeName, newEmptyNode())],
        nnkStmtList.newTree(),
        nnkMethodDef
    )

    if outputs.len > 0:
        proc writeOutput(name, value: NimNode) =
            invoke.body.add(
                nnkCall.newTree(
                    nnkDotExpr.newTree(
                        nnkDotExpr.newTree(
                            ident("vs"),
                            name
                        ),
                        ident("write")
                    ),
                    value
                )
            )

        if outputs.len > 1:
            let output = nnkLetSection.newTree(
                nnkVarTuple.newTree()
            )
            for i in 0 ..< outputs.len:
                output[0].add(ident("o" & $i))
            output[0].add(newEmptyNode())
            output[0].add(originalCall)
            invoke.body.add(output)

            for i, output in outputs:
                writeOutput(ident("o" & $i), ident("o" & $i))
        else:
            writeOutput(ident("o0"), originalCall)
    else:
        invoke.body.add(originalCall)

    result = invoke


template metadata(T, tn, fn, inputs, outputs): untyped =
    method metadata*(vs: T): VSHostMeta =
        return (tn, fn, inputs, outputs)
proc generateMetaDataProc(a: NimNode, originalProcName: string, typeName: NimNode, outputs: seq[OutputPortNode], inputs: seq[InputPortNode]): NimNode =
    let inputsSeq = nnkPrefix.newTree(ident("@"), nnkBracket.newTree())
    for input in inputs:
        inputsSeq[1].add(
            nnkPar.newTree(
                newLit($input.name),
                newLit(repr(input.sign)),
                newLit(if input.default.kind == nnkEmpty: "" else: repr(input.default))
            )
        )
    let outputsSeq = nnkPrefix.newTree(ident("@"), nnkBracket.newTree())
    for output in outputs:
        outputsSeq[1].add(
            nnkPar.newTree(
                newLit($output.name),
                newLit(repr(output.sign)),
                newLit("")
            )
        )
    result = getAst(metadata(typeName, newLit($typeName), originalProcName, inputsSeq, outputsSeq))


proc generateCreatorProc(a: NimNode, originalProcName: string, creatorProcName: NimNode, typeName: NimNode, outputs: seq[OutputPortNode], inputs: seq[InputPortNode]): NimNode =
    let creator = newProc(
        nnkPostfix.newTree(ident("*"), creatorProcName),
        [typeName],
        nnkStmtList.newTree(
            nnkLetSection.newTree(
                nnkIdentDefs.newTree(
                    ident("vs"),
                    newEmptyNode(),
                    nnkCall.newTree(nnkDotExpr.newTree(typeName, ident("new")))
                )
            ),
            nnkAsgn.newTree(
                nnkDotExpr.newTree(
                    ident("vs"),
                    ident("name")
                ),
                newLit(originalProcName)
            ),
            nnkAsgn.newTree(
                nnkDotExpr.newTree(
                    ident("vs"),
                    ident("flow")
                ),
                nnkPrefix.newTree(ident("@"), nnkBracket.newTree())
            )
        )
    )
    for i, input in inputs:
        closureScope:
            let ii = i
            creator.body.add(
                nnkAsgn.newTree(
                    nnkDotExpr.newTree(
                        ident("vs"),
                        ident("i" & $ii)
                    ),
                    nnkCall.newTree(
                        ident("newVSPort"),
                        newLit($input.name),
                        input.sign,
                        nnkDotExpr.newTree(
                            ident("VSPortKind"),
                            ident("Input")
                        )
                    )
                )
            )
    for i, output in outputs:
        closureScope:
            let ii = i
            creator.body.add(
                nnkAsgn.newTree(
                    nnkDotExpr.newTree(
                        ident("vs"),
                        ident("o" & $ii)
                    ),
                    nnkCall.newTree(
                        ident("newVSPort"),
                        newLit($output.name),
                        output.sign,
                        nnkDotExpr.newTree(
                            ident("VSPortKind"),
                            ident("Output")
                        )
                    )
                )
            )
            creator.body.add(
                nnkAsgn.newTree(
                    nnkDotExpr.newTree(
                        nnkDotExpr.newTree(
                            ident("vs"),
                            ident("o" & $ii)
                        ),
                        ident("readImpl")
                    ),
                    newProc(
                        newEmptyNode(),
                        [output.sign],
                        nnkStmtList.newTree(
                            newIfStmt(
                                (
                                    nnkCall.newTree(ident("not"),
                                    nnkDotExpr.newTree(ident("vs"), ident("frozen"))), nnkCall.newTree(nnkDotExpr.newTree(ident("vs"), ident("invoke")))
                                )
                            ),
                            nnkReturnStmt.newTree(
                                nnkCall.newTree(
                                    nnkDotExpr.newTree(
                                        nnkDotExpr.newTree(
                                            ident("vs"),
                                            ident("o" & $ii)
                                        ),
                                        ident("rawData")
                                    )
                                )
                            )
                        ),
                        nnkLambda
                    )
                )
            )
    creator.body.add(
        nnkAsgn.newTree(
            ident("result"),
            ident("vs")
        )
    )
    # echo "repr ", repr(creator)
    result = creator


proc generateDestroyMethod(a: NimNode, typeName: NimNode, outputs: seq[OutputPortNode], inputs: seq[InputPortNode]): NimNode =
    let destroy = newProc(
        nnkPostfix.newTree(ident("*"), ident("destroy")),
        [newEmptyNode(), nnkIdentDefs.newTree(ident("vs"), typeName, newEmptyNode())],
        nnkStmtList.newTree(),
        nnkMethodDef
    )

    for i, input in inputs:
        destroy.body.add(
            nnkCall.newTree(
                nnkDotExpr.newTree(
                    nnkDotExpr.newTree(
                        ident("vs"),
                        ident("i" & $i)
                    ),
                    ident("destroy")
                )
            )
        )

    for i, output in outputs:
        destroy.body.add(
            nnkCall.newTree(
                nnkDotExpr.newTree(
                    nnkDotExpr.newTree(
                        ident("vs"),
                        ident("o" & $i)
                    ),
                    ident("destroy")
                )
            )
        )

    result = destroy


proc generateGetPortMethod(a: NimNode, typeName: NimNode, outputs: seq[OutputPortNode], inputs: seq[InputPortNode]): NimNode =
    let getPort = newProc(
        nnkPostfix.newTree(ident("*"), ident("getPort")),
        [
            ident("Variant"),
            nnkIdentDefs.newTree(ident("vs"), typeName, newEmptyNode()),
            nnkIdentDefs.newTree(ident("name"), ident("string"), newEmptyNode()),
            nnkIdentDefs.newTree(ident("clone"), ident("bool"), ident("false")),
            nnkIdentDefs.newTree(ident("cloneAs"), ident("VSPortKind"), nnkDotExpr.newTree(ident("VSPortKind"), ident("Output")))
        ],
        nnkStmtList.newTree(nnkIfStmt.newTree()),
        nnkMethodDef
    )

    for i, input in inputs:
        closureScope:
            let port = ident("i" & $i)
            getPort.body[0].add(
                nnkElifBranch.newTree(
                    nnkInfix.newTree(
                        ident("=="),
                        ident("name"),
                        newLit($port)
                    ),
                    nnkStmtList.newTree(
                        nnkReturnStmt.newTree(
                            nnkCall.newTree(
                                ident("newVariant"),
                                nnkIfExpr.newTree(
                                    nnkElifExpr.newTree(
                                        ident("clone"),
                                        nnkCall.newTree(
                                            nnkDotExpr.newTree(
                                                nnkDotExpr.newTree(
                                                    ident("vs"),
                                                    port
                                                ),
                                                ident("clone")
                                            ),
                                            ident("cloneAs")
                                        )
                                    ),
                                    nnkElseExpr.newTree(
                                        nnkDotExpr.newTree(
                                            ident("vs"),
                                            port
                                        )
                                    )
                                )
                            )
                        )
                    )
                )
            )

    for i, output in outputs:
        closureScope:
            let port = ident("o" & $i)
            getPort.body[0].add(
                nnkElifBranch.newTree(
                    nnkInfix.newTree(
                        ident("=="),
                        ident("name"),
                        newLit($port)
                    ),
                    nnkStmtList.newTree(
                        nnkReturnStmt.newTree(
                            nnkCall.newTree(
                                ident("newVariant"),
                                nnkIfExpr.newTree(
                                    nnkElifExpr.newTree(
                                        ident("clone"),
                                        nnkCall.newTree(
                                            nnkDotExpr.newTree(
                                                nnkDotExpr.newTree(
                                                    ident("vs"),
                                                    port
                                                ),
                                                ident("clone")
                                            ),
                                            ident("cloneAs")
                                        )
                                    ),
                                    nnkElseExpr.newTree(
                                        nnkDotExpr.newTree(
                                            ident("vs"),
                                            port
                                        )
                                    )
                                )
                            )
                        )
                    )
                )
            )

    result = getPort


proc generateConnectMethod(a: NimNode, typeName: NimNode, outputs: seq[OutputPortNode], inputs: seq[InputPortNode]): NimNode =
    let connect = newProc(
        nnkPostfix.newTree(ident("*"), ident("connect")),
        [
            newEmptyNode(),
            nnkIdentDefs.newTree(ident("vs"), typeName, newEmptyNode()),
            nnkIdentDefs.newTree(ident("port"), ident("string"), newEmptyNode()),
            nnkIdentDefs.newTree(ident("port2"), ident("Variant"), newEmptyNode())
        ],
        nnkStmtList.newTree(nnkIfStmt.newTree()),
        nnkMethodDef
    )

    for i, input in inputs:
        closureScope:
            let port = ident("i" & $i)
            connect.body[0].add(
                nnkElifBranch.newTree(
                    nnkInfix.newTree(
                        ident("=="),
                        ident("port"),
                        newLit($port)
                    ),
                    nnkStmtList.newTree(
                        nnkCall.newTree(
                            nnkDotExpr.newTree(
                                nnkDotExpr.newTree(
                                    ident("vs"),
                                    port
                                ),
                                ident("connect")
                            ),
                            ident("port2")
                        )
                    )
                )
            )

    for i, output in outputs:
        closureScope:
            let port = ident("o" & $i)
            connect.body[0].add(
                nnkElifBranch.newTree(
                    nnkInfix.newTree(
                        ident("=="),
                        ident("port"),
                        newLit($port)
                    ),
                    nnkStmtList.newTree(
                        nnkCall.newTree(
                            nnkDotExpr.newTree(
                                nnkDotExpr.newTree(
                                    ident("vs"),
                                    port
                                ),
                                ident("connect")
                            ),
                            ident("port2")
                        )
                    )
                )
            )

    result = connect

proc toVsHost(originalProcName: string, a: NimNode): NimNode =
    case a.kind:
        of nnkProcDef, nnkMethodDef:
            discard
        else:
            error "Unexpected kind. For proc and method only!"

    let outputs = generateOutputs(a)
    let inputs = generateInputs(a)

    var originalProcName = originalProcName
    if compileTimeRegistry.hasKey(originalProcName):
        for input in inputs:
            let sign = repr(input.sign)
            let index = sign.find(AllChars - Letters)
            if index > -1:
                originalProcName &= sign[0 ..< index].capitalizeAscii()
            else:
                originalProcName &= sign.capitalizeAscii()

    result = nnkStmtList.newTree(a)

    let typeName = ident(originalProcName.capitalizeAscii() & "VSHost")

    let typeWithFields = generateTypeWithFields(a, originalProcName, typeName, outputs, inputs)
    result.add(typeWithFields)

    let invokeMethod = generateInvokeMethod(a, typeName, outputs, inputs)
    result.add(invokeMethod)

    let metadataProc = generateMetaDataProc(a, originalProcName, typeName, outputs, inputs)
    result.add(metadataProc)

    let creatorProcName = ident("new" & $typeName)
    let creatorProc = generateCreatorProc(a, originalProcName, creatorProcName, typeName, outputs, inputs)
    result.add(creatorProc)

    let getPortMethod = generateGetPortMethod(a, typeName, outputs, inputs)
    result.add(getPortMethod)

    let connectMethod = generateConnectMethod(a, typeName, outputs, inputs)
    result.add(connectMethod)

    let destroyMethod = generateDestroyMethod(a, typeName, outputs, inputs)
    result.add(destroyMethod)

    result.add(
        nnkCall.newTree(
            ident("putHostToRegistry"),
            newLit($typeName),
            newProc(
                newEmptyNode(),
                [ident("VSHost")],
                nnkStmtList.newTree(
                    nnkCall.newTree(
                        ident("VSHost"),
                        nnkCall.newTree(
                            creatorProcName
                        )
                    )
                ),
                nnkLambda
            )
        )
    )

    compileTimeRegistry[originalProcName] = result

    # echo repr(result)


macro vshost*(procDef: untyped, a: untyped = nil): typed =
    # echo treeRepr(procDef), " \na ", if not a.isNil: treeRepr(a) else: "nil"
    if not a.isNil and a.kind != nnkNilLit:
        result = toVsHost($a, procDef)
    else:
        result = toVsHost(procDef[0].getName(), procDef)

    echo "vshost ", repr(result)
