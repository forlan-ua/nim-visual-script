import macros, strutils, tables, strutils, typetraits, variant, parseutils


type VSPortKind* {.pure.} = enum
    Input
    Output


type VSPort*[T] = ref object of RootObj
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
    p1.connect(p2.get(VSPort[T]))


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
    result = new(VSPort[T])
    result.name = name
    result.kind = kind
    result.connections = @[]

proc newVSPort*(T: typedesc, kind: VSPortKind): VSPort[T] =
    newVSPort("", T, kind)


type VSHostMeta* = tuple[typeName, procName: string, inputs: seq[tuple[name, sign, default: string]], outputs: seq[tuple[name, sign, default: string]]]
type VSHost* = ref object of RootObj
    name*: string
    frozen: bool


method invoke*(vs: VSHost) {.base.} = discard
method metadata*(vs: VSHost): VSHostMeta {.base.} = discard
method getPort*(vs: VSHost, name: string): Variant {.base.} = discard
method connect*(vs: VSHost, port: string, vs2: VSHost, port2: string) {.base.} = discard


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

proc getHostFromRegistry*(name: string): VSHost =
    if not hostRegistry.hasKey(name):
        raise newException(ValueError, "`" & name & "` has not been found in the registry.")
    hostRegistry[name]()

proc getHostFromRegistry*(T: typedesc[VSHost]): T =
    type TT = T
    return getHostFromRegistry[T](T.name).TT


####
var compileTimeRegistry {.compiletime.} = initTable[string, NimNode]()

proc getName(n: NimNode): string =
    if n.kind == nnkIdent:
        return $n
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


proc generateOriginalFunctionCall(a: NimNode, originalProcName: string, inputs: seq[InputPortNode]): NimNode =
    let invokeRes = nnkCall.newTree(
        a[0]
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

proc generateInvokeMethod(a: NimNode, originalProcName: string, typeName: NimNode, originalCall: NimNode, outputs: seq[OutputPortNode], inputs: seq[InputPortNode]): NimNode =
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
    proc metadata*(vs: typedesc[T]): VSHostMeta =
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
        [ident("Variant"), nnkIdentDefs.newTree(ident("vs"), typeName, newEmptyNode()), nnkIdentDefs.newTree(ident("name"), ident("string"), newEmptyNode())],
        nnkStmtList.newTree(nnkIfStmt.newTree()),
        nnkMethodDef
    )

    for i, input in inputs:
        getPort.body[0].add(
            nnkElifBranch.newTree(
                nnkInfix.newTree(
                    ident("=="),
                    ident("name"),
                    newLit("i" & $i)
                ),
                nnkStmtList.newTree(
                    nnkReturnStmt.newTree(
                        nnkCall.newTree(
                            ident("newVariant"),
                            nnkDotExpr.newTree(
                                ident("vs"),
                                ident("i" & $i)
                            )
                        )
                    )
                )
            )
        )

    for i, output in outputs:
        getPort.body[0].add(
            nnkElifBranch.newTree(
                nnkInfix.newTree(
                    ident("=="),
                    ident("name"),
                    newLit("o" & $i)
                ),
                nnkStmtList.newTree(
                    nnkReturnStmt.newTree(
                        nnkCall.newTree(
                            ident("newVariant"),
                            nnkDotExpr.newTree(
                                ident("vs"),
                                ident("o" & $i)
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
            nnkIdentDefs.newTree(ident("vs2"), ident("VSHost"), newEmptyNode()),
            nnkIdentDefs.newTree(ident("port2"), ident("string"), newEmptyNode())
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
                            nnkCall.newTree(
                                nnkDotExpr.newTree(
                                    ident("vs2"),
                                    ident("getPort")
                                ),
                                ident("port2")
                            )
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
                            nnkCall.newTree(
                                nnkDotExpr.newTree(
                                    ident("vs2"),
                                    ident("getPort")
                                ),
                                ident("port2")
                            )
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

    let originalCall = generateOriginalFunctionCall(a, originalProcName, inputs)
    let invokeMethod = generateInvokeMethod(a, originalProcName, typeName, originalCall, outputs, inputs)
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

    echo repr(result)


macro vshost*(name: untyped, a: untyped = nil): typed =
    if not a.isNil:
        toVsHost($name, a)
    else:
        toVsHost(name[0].getName(), name)


type VSNetwork* = ref object of VSHost
    ports*: seq[Variant]
    hosts*: seq[VSHost]
    runner*: proc()


proc destroy*(net: VSNetwork) =
    for host in net.hosts:
        host.destroy()


proc clean*(net: VSNetwork) =
    for host in net.hosts:
        host.frozen = false


var networksRegistry = initTable[string, VSNetwork]()
proc putNetworkToRegistry*(net: VSNetwork) =
    networksRegistry[net.name] = net
proc getNetworkFromRegistry*(name: string): VSNetwork =
    networksRegistry.getOrDefault(name)


var dispatchRegistry = initTable[string, seq[string]]()
proc putNetworksToDispatchRegistry*(event: string, networks: varargs[string]) =
    var nets = dispatchRegistry.getOrDefault(event)
    if nets.isNil:
        nets = @[]
    for net in networks:
        if nets.find(net) == -1:
            nets.add(net)
    dispatchRegistry[event] = nets

proc removeNetworksFromDispatchRegistry*(event: string, networks: varargs[string]) =
    var nets = dispatchRegistry.getOrDefault(event)
    if nets.isNil:
        return
    for net in networks:
        let ind = nets.find(net)
        if ind > -1:
            nets.del(ind)
    dispatchRegistry[event] = nets

iterator eachNetwork*(event: string): VSNetwork =
    let networks = dispatchRegistry.getOrDefault(event)
    for net in networks:
        let n = getNetworkFromRegistry(net)
        if not n.isNil:
            yield n

macro dispatchNetwork*(event: untyped, args: varargs[untyped]): untyped =
    var res = nnkStmtList.newTree()
    proc portData(i: int, arg: NimNode): NimNode =
        nnkCall.newTree(
            nnkDotExpr.newTree(
                nnkCall.newTree(
                    nnkDotExpr.newTree(
                        nnkBracketExpr.newTree(
                            nnkDotExpr.newTree(
                                ident("n"),
                                ident("ports")
                            ),
                            newLit(i)
                        ),
                        ident("get")
                    ),
                    nnkBracketExpr.newTree(
                        ident("VSPort"),
                        nnkDotExpr.newTree(
                            arg,
                            ident("type")
                        )
                    )
                ),
                ident("write")
            ),
            arg
        )

    res.add(
        nnkForStmt.newTree(
            newIdentNode("n"),
            nnkCall.newTree(
                newIdentNode("eachNetwork"),
                event
            ),
            nnkStmtList.newTree()
        )
    )

    for i, arg in args:
        res[0][2].add(portData(i, arg))

    res[0][2].add(
        nnkCall.newTree(
            nnkDotExpr.newTree(
                newIdentNode("n"),
                newIdentNode("runner")
            )
        )
    )

    result = res

    echo repr(result)


proc generateNetwork*(source: string): VSNetwork {.discardable.} =
    var localRegistry = initTable[string, VSHost]()

    var inputs = newSeq[Variant]()
    var hosts = newSeq[VSHost]()

    var newtworkName: string
    var dispatcherName: string

    var index: string
    var name: string
    var start: int

    start += source.parseUntil(newtworkName, '>', start) + 1
    start += source.parseUntil(dispatcherName, '\n', start) + 1
    start.inc

    var port2Index, port2Name: string
    var port1Index, port1Name: string


    while start < source.len:
        start += source.parseUntil(index, ' ', start) + 1
        if start >= source.len:
            break
        start += source.parseUntil(name, '\n', start) + 1
        
        let host = getHostFromRegistry(name)
        localRegistry[index] = host
        hosts.add(host)

        while true:
            start += source.parseUntil(port1Index, {'.', '\n'}, start) + 1
            if port1Index.len == 0:
                break
            start += source.parseUntil(port1Name, '>', start) + 1
            start += source.parseUntil(port2Index, {'.', '\n'}, start) + 1
            if port2Index[0].isDigit():
                start += source.parseUntil(port2Name, '\n', start) + 1
            else:
                port2Name = ""

            if port2Name.len > 0:
                localRegistry[port1Index].connect(port1Name, localRegistry[port2Index], port2Name)
            else:
                let ind = parseInt(port2Index.substr(1, port2Index.high))
                inputs.insert(localRegistry[port1Index].getPort(port1Name), ind)

            # echo "CONNECTION: ", port1Index, ".", port1Name, "->", port2Index, ".", port2Name

    let f = index

    var flow = proc() {.closure.} =
        echo " "
        for ind in f.split('>'):
            hosts[parseInt(ind.strip())].invokeFlow()
        echo " "

    result = VSNetwork(name: newtworkName, ports: inputs, hosts: hosts, runner: flow)
    putNetworkToRegistry(result)
    putNetworksToDispatchRegistry(dispatcherName, newtworkName)