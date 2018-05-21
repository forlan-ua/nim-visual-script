import macros, strutils, tables, strutils, typetraits


type VSPortKind* {.pure.} = enum
    Input
    Output


type VSPort*[T] = ref object of RootObj
    name*: string
    case kind*: VSPortKind:
        of Input:
            source: VSPort[T]
        of Output:
            data: T
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
    if not vs.source.isNil:
        return vs.source.readOutput()


proc write*[T](vs: VSPort[T], val: T) =
    assert(vs.kind == VSPortKind.Output)
    vs.data = val
    for connection in vs.connections:
        connection.source = vs


proc readOutput*[T](vs: VSPort[T]): T =
    assert(vs.kind == VSPortKind.Output)
    vs.readImpl()


proc rawData*[T](vs: VSPort[T]): T =
    assert(vs.kind == VSPortKind.Output)
    vs.data 

proc newVSPort*(name: string, T: typedesc, kind: VSPortKind): VSPort[T] =
    result = new(VSPort[T])
    result.name = name
    result.kind = kind
    result.connections = @[]

proc newVSPort*(T: typedesc, kind: VSPortKind): VSPort[T] =
    newVSPort("", T, kind)


type VSHostMeta* = tuple[typeName, procName: string, inputs: seq[tuple[name, sign, default: string]], outputs: seq[tuple[name, sign, default: string]]]
type VSHost* = ref object of RootObj
    name: string
    frozen: bool


method invoke*(vs: VSHost) {.base.} = discard
method metadata*(vs: VSHost): VSHostMeta {.base.} = discard
method destroy*(vs: VSHost) {.base.} = discard
proc flow*(vs: VSHost): bool = vs.frozen

proc invokeFlow*(vs: VSHost) =
    vs.frozen = true
    vs.invoke()

####
var hostRegistry = initTable[string, proc(): VSHost]()

proc putHostToRegistry*(T: string, creator: proc(): VSHost) =
    hostRegistry[T] = creator

proc putHostToRegistry*(T: typedesc[VSHost], creator: proc(): VSHost) =
    putHostToRegistry(T.name, creator)

proc getHostFromRegistry*[T](name: string): T =
    if not hostRegistry.hasKey(name):
        raise newException(ValueError, "`" & name & "` has not been found in the registry.")
    type TT = T
    return hostRegistry[name]().TT

proc getHostFromRegistry*(T: typedesc[VSHost]): T =
    getHostFromRegistry[T](T.name)


####
var compileTimeRegistry {.compiletime.} = initTable[string, NimNode]()

proc getName(n: NimNode): string =
    if n.kind == nnkIdent:
        return $(n.ident)
    elif n.kind == nnkPostfix:
        return $(n[1].ident)

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
    
    for output in outputs:
        recList.add(createPortNode(output.name, output.sign))

    for input in inputs:
        if hostTypeHasArg(input.name):
            error "Argument " & $input.name & " has been already setted for function " & originalProcName & ". Please check input and output arguments."
        recList.add(createPortNode(input.name, input.sign))


proc generateOriginalFunctionCall(a: NimNode, originalProcName: string, inputs: seq[InputPortNode]): NimNode =
    let invokeRes = nnkCall.newTree(
        a[0]
    )
    for input in inputs:
        invokeRes.add(
            nnkCall.newTree(
                nnkDotExpr.newTree(
                    nnkDotExpr.newTree(
                        ident("vs"),
                        input.name
                    ),
                    ident("read")
                )
            )
        )
    result = invokeRes

proc generateInvokeMethod(a: NimNode, originalProcName: string, typeName: NimNode, originalCall: NimNode, outputs: seq[OutputPortNode], inputs: seq[InputPortNode]): NimNode =
    let invoke = newProc(
        nnkPostfix.newTree(ident("*"), ident("invoke")), 
        [newEmptyNode(), nnkIdentDefs.newTree(ident("vs"), typeName, newEmptyNode())], 
        nnkStmtList.newTree(), 
        nnkMethodDef
    )

    # for input in inputs:
    #     invoke.body.add(
    #         nnkIfStmt.newTree(
    #             nnkElifBranch.newTree(
    #                 nnkPrefix.newTree(
    #                     ident("not"),
    #                     nnkDotExpr.newTree(
    #                         nnkDotExpr.newTree(
    #                             ident("vs"),
    #                             input.name
    #                         ),
    #                         ident("hasValue")
    #                     )
    #                 ),
    #                 nnkStmtList.newTree(nnkReturnStmt.newTree(newEmptyNode()))
    #             )
    #         )    
    #     )

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
                writeOutput(output.name, ident("o" & $i))
        else:
            writeOutput(outputs[0].name, originalCall)
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
            )
        )
    )
    creator.body.add(
        nnkAsgn.newTree(
            nnkDotExpr.newTree(
                ident("vs"),
                ident("name")
            ),
            newLit(originalProcName)
        )
    )
    for input in inputs:
        creator.body.add(
            nnkAsgn.newTree(
                nnkDotExpr.newTree(
                    ident("vs"),
                    input.name
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
    for output in outputs:
        creator.body.add(
            nnkAsgn.newTree(
                nnkDotExpr.newTree(
                    ident("vs"),
                    output.name
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
                        output.name
                    ),
                    ident("readImpl")
                ),
                newProc(
                    newEmptyNode(),
                    [output.sign],
                    nnkStmtList.newTree(
                        newIfStmt(
                            (nnkCall.newTree(ident("not"), nnkDotExpr.newTree(ident("vs"), ident("frozen"))), nnkCall.newTree(nnkDotExpr.newTree(ident("vs"), ident("invoke"))))
                        ),
                        nnkReturnStmt.newTree(
                            nnkCall.newTree(
                                nnkDotExpr.newTree(
                                    nnkDotExpr.newTree(
                                        ident("vs"),
                                        output.name
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
    result = creator


proc generateDestroyMethod(a: NimNode, typeName: NimNode, outputs: seq[OutputPortNode], inputs: seq[InputPortNode]): NimNode =
    let destroy = newProc(
        nnkPostfix.newTree(ident("*"), ident("destroy")),
        [newEmptyNode(), nnkIdentDefs.newTree(ident("vs"), typeName, newEmptyNode())],
        nnkStmtList.newTree(),
        nnkMethodDef
    )

    for input in inputs:
        destroy.body.add(
            nnkCall.newTree(
                nnkDotExpr.newTree(
                    nnkDotExpr.newTree(
                        ident("vs"),
                        input.name
                    ),
                    ident("destroy")
                )
            )
        )

    for output in outputs:
        destroy.body.add(
            nnkCall.newTree(
                nnkDotExpr.newTree(
                    nnkDotExpr.newTree(
                        ident("vs"),
                        output.name
                    ),
                    ident("destroy")
                )
            )
        )

    result = destroy


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

    let originalCall = generateOriginalFunctionCall(a, originalProcName, inputs)
    let invokeMethod = generateInvokeMethod(a, originalProcName, typeName, originalCall, outputs, inputs)
    result.add(invokeMethod)

    let metadataProc = generateMetaDataProc(a, originalProcName, typeName, outputs, inputs)
    result.add(metadataProc)
    
    let creatorProcName = ident("new" & $typeName)
    let creatorProc = generateCreatorProc(a, originalProcName, creatorProcName, typeName, outputs, inputs)
    result.add(creatorProc)
    
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

    echo repr(result)


macro vshost*(name: untyped, a: untyped = nil): typed =
    if not a.isNil:
        toVsHost($name, a)
    else:
        toVsHost(name[0].getName(), name)


type VSNetwork* = ref object of VSHost
    hosts*: seq[VSHost]
    flow*: proc()


proc destroy*(net: VSNetwork) =
    for host in net.hosts:
        host.destroy()


proc clean*(net: VSNetwork) =
    for host in net.hosts:
        host.frozen = false