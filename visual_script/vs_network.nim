import tables, variant, macros, logging
import vs_host, vs_std


type FlowForNetwork* = ref object
    ports*: seq[Variant]
    accessPoints: seq[VSHost]

proc run*(flow: FlowForNetwork) =
    for h in flow.accessPoints:
        h.invokeFlow()


type VSNetwork* = ref object of VSHost
    hosts*: seq[VSHost]
    flows*: Table[string, FlowForNetwork]


proc destroy*(net: VSNetwork) =
    for host in net.hosts:
        host.destroy()


var networksRegistry = initTable[string, VSNetwork]()
proc putNetworkToRegistry*(net: VSNetwork) =
    networksRegistry[net.name] = net
proc getNetworkFromRegistry*(name: string): VSNetwork =
    networksRegistry.getOrDefault(name)


type Dispatcher = ref object
    event*: string
    networks*: seq[string]
    ports*: seq[tuple[name: string, sign: string]]


var dispatchRegistry = initTable[string, Dispatcher]()

proc putNetworkDispatcherToRegistry*(event: string, ports: seq[tuple[name: string, sign: string]]) =
    var dispatcher = dispatchRegistry.getOrDefault(event)
    if not dispatcher.isNil:
        if not dispatcher.ports.isNil:
            raise newException(ValueError, "Dispatcher `" & event & "` has been already registered.")
        dispatcher.ports = ports
    else:
        dispatchRegistry[event] = Dispatcher(event: event, networks: @[], ports: ports)

proc putNetworksToDispatchRegistry*(event: string, networks: varargs[string]) =
    var dispatcher = dispatchRegistry.getOrDefault(event)
    if dispatcher.isNil:
        dispatcher = Dispatcher(event: event, networks: @[])
    for net in networks:
        if dispatcher.networks.find(net) == -1:
            dispatcher.networks.add(net)
    dispatchRegistry[event] = dispatcher

proc removeNetworksFromDispatchRegistry*(event: string, networks: varargs[string]) =
    var dispatcher = dispatchRegistry.getOrDefault(event)
    if dispatcher.isNil:
        warn "Dispatcher `" & event & "` has not been registered."
        return
    for net in networks:
        let ind = dispatcher.networks.find(net)
        if ind > -1:
            dispatcher.networks.del(ind)

iterator eachNetwork*(event: string): FlowForNetwork =
    let dispatcher = dispatchRegistry.getOrDefault(event)
    if not dispatcher.isNil and dispatcher.ports.isNil:
        for net in dispatcher.networks:
            let n = getNetworkFromRegistry(net)
            if not n.isNil:
                let flow = n.flows.getOrDefault(event)
                if not flow.isNil:
                    yield flow

iterator eachDispatcher*(): Dispatcher =
    for d in dispatchRegistry.values():
        if not d.ports.isNil:
            yield d

macro dispatchNetwork*(event: untyped, args: varargs[untyped]): untyped =
    result = nnkCall.newTree(
        ident("dispatchNetwork_" & $event)
    )
    for arg in args:
        result.add(arg)

proc genVsDispatcherReg(name, args: NimNode): NimNode =
    let argsBody = nnkBracket.newTree()
    result = nnkCall.newTree(
        ident("putNetworkDispatcherToRegistry"),
        name,
        prefix(argsBody, "@")
    )
    for i, arg in args:
        argsBody.add(
            nnkPar.newTree(
                newLit($arg[0]),
                newLit($arg[1])
            )
        )
        

proc genVsDispatcherProc(name, args: NimNode): NimNode =
    result = newProc(
        postfix(ident("dispatchNetwork_" & $name), "*"),
        [newEmptyNode()],
        newStmtList()
    )
    
    let n = genSym(nskForVar, "n")
    let res = nnkStmtList.newTree()
    
    proc portData(i: int, arg: NimNode): NimNode =
        nnkCall.newTree(
            nnkDotExpr.newTree(
                nnkCall.newTree(
                    nnkDotExpr.newTree(
                        nnkBracketExpr.newTree(
                            nnkDotExpr.newTree(
                                n,
                                ident("ports")
                            ),
                            newLit(i)
                        ),
                        ident("get")
                    ),
                    nnkBracketExpr.newTree(
                        ident("VSPort"),
                        arg[1]
                    )
                ),
                ident("write")
            ),
            arg[0]
        )
    
    let forbody = nnkStmtList.newTree()
    res.add(
        nnkForStmt.newTree(
            n,
            nnkCall.newTree(
                newIdentNode("eachNetwork"),
                name
            ),
            forbody
        )
    )

    for i, arg in args:
        result.params.add(
            nnkIdentDefs.newTree(
                arg[0],
                arg[1],
                newEmptyNode()
            )
        )
        forbody.add(portData(i, arg))

    forbody.add(
        nnkCall.newTree(
            nnkDotExpr.newTree(
                n,
                newIdentNode("run")
            )
        )
    )

    result.body = res


macro registerNetworkDispatcher*(name: untyped, args: untyped): typed =
    result = nnkStmtList.newTree(
        genVsDispatcherReg(name, args),
        genVsDispatcherProc(name, args)
    )

    echo repr(result)


proc generateNetwork*(source: string): VSNetwork {.discardable.} =
    let net = VSNetwork.new()
    net.hosts = @[]
    net.flows = initTable[string, FlowForNetwork]()
    
    var start: int
    start += source.parseUntil(net.name, '\n', start) + 1
    start.inc

    var localHostMapper = initTable[string, int]()
    var localFlowMapper = initTable[string, string]()

    var localId: string
    var name: string
    
    echo "<<<<<<<<<<<<<<<<<<<<<<"
    echo net.name
    echo " "
    echo "Parse Dispatchers:"

    while source[start] != '\n':
        start += source.parseUntil(localId, ' ', start) + 1
        start += source.parseUntil(name, '\n', start) + 1

        localFlowMapper[localId] = name
        let flow = FlowForNetwork.new()
        flow.ports = @[]
        flow.accessPoints = @[]
        net.flows[name] = flow

        putNetworksToDispatchRegistry(name, net.name)

        echo name
    start.inc
    
    echo " "
    echo "Parse Dispatchers:"

    while source[start] != '\n':
        start += source.parseUntil(localId, ' ', start) + 1
        start += source.parseUntil(name, '\n', start) + 1
        
        net.hosts.add(getHostFromRegistry(name))
        localHostMapper[localId] = net.hosts.high

        echo name
    start.inc

    echo " "
    echo "Parse Ports:"

    var host1LocalId, port1Name: string
    var host2LocalId, port2Name: string

    while source[start] != '\n':
        start += source.parseUntil(host1LocalId, '.', start) + 1
        start += source.parseUntil(port1Name, {'>', '='}, start)

        if source[start] == '>':
            start += source.parseUntil(host2LocalId, '.', start + 1) + 2
            start += source.parseUntil(port2Name, '\n', start) + 1

            if localHostMapper.hasKey(host2LocalId):
                let host1 = net.hosts[localHostMapper[host1LocalId]]
                let host2 = net.hosts[localHostMapper[host2LocalId]]
                echo "Connect Port `", host1.name, ".", port1Name, "` to `", host2.name, ".", port2Name, "`"
                host1.connect(port1Name, host2, port2Name)
            else:
                let host = net.hosts[localHostMapper[host1LocalId]]
                let flowName = localFlowMapper[host2LocalId]
                let flow = net.flows[flowName]
                let ind = parseInt(port2Name.substr(1, port2Name.high))
                if flow.ports.len <= ind:
                    flow.ports.setLen(ind + 1)
                if flow.ports[ind].isEmpty:
                    flow.ports[ind] = host.getPort(port1Name, clone=true)
                    echo "Save port `", host.name, ".", port1Name, "` as `", ind, "` input for dispatcher ", flowName
                echo "Connect Port `", host.name, ".", port1Name, "` to `", flowName, ".", ind, "`"
                host.connect(port1Name, flow.ports[ind])
        elif source[start] == '=':
            assert(net.hosts[localHostMapper[host1LocalId]] of LitVSHost)

            start += source.parseUntil(port2Name, '\n', start + 1) + 2
            let host = net.hosts[localHostMapper[host1LocalId]]
            host.LitVSHost.setValue(port2Name)
    start.inc

    echo " "
    echo "Parse Flow"

    while source[start] notin {'\n', '#'}:
        start += source.parseUntil(host1LocalId, '>', start) + 1
        case source[start]:
            of '+':
                start += source.parseUntil(host2LocalId, '\n', start + 1) + 2

                let host1 = net.hosts[localHostMapper[host1LocalId]]
                let host2 = net.hosts[localHostMapper[host2LocalId]]

                host1.IfVSHost.flow.add(host2)
            of '-':
                start += source.parseUntil(host2LocalId, '\n', start + 1) + 2
                
                let host1 = net.hosts[localHostMapper[host1LocalId]]
                let host2 = net.hosts[localHostMapper[host2LocalId]]

                host1.IfVSHost.falseFlow.add(host2)
            else:
                start += source.parseUntil(host2LocalId, '\n', start) + 1
                if localHostMapper.hasKey(host1LocalId):
                    let host1 = net.hosts[localHostMapper[host1LocalId]]
                    let host2 = net.hosts[localHostMapper[host2LocalId]]
                    host1.flow.add(host2)
                else:
                    let flow = net.flows[localFlowMapper[host1LocalId]]
                    let host = net.hosts[localHostMapper[host2LocalId]]
                    flow.accessPoints.add(host)

    echo ">>>>>>>>>>>>>>>>>>>>>>>"
    putNetworkToRegistry(net)

    result = net