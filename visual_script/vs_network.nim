import tables, variant, macros
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

iterator eachNetwork*(event: string): FlowForNetwork =
    let networks = dispatchRegistry.getOrDefault(event)
    for net in networks:
        let n = getNetworkFromRegistry(net)
        if not n.isNil:
            let flow = n.flows.getOrDefault(event)
            if not flow.isNil:
                yield flow

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
                newIdentNode("run")
            )
        )
    )

    result = res

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