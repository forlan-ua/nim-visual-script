import strutils, tables

import nimx / [
    types, view, button, text_field, panel_view, context, event,
    view_dragging_listener, font, formatted_text, gesture_detector,
    scroll_view
]

import vse_types
export vse_types
import vse_colors
import vse_host
import vse_port
import vse_metadata_cache

proc connect*(v: VSNetworkView, a, b: VSPortView)=
    if a notin b.connections and b notin a.connections:
        a.connections.add(b)
        b.connections.add(a)
        if not a.orientation:
            v.connections.add((a: a, b: b))
        else:
            v.connections.add((a: b, b: a))

proc disconnect*(v: VSNetworkView, a: VSPortView)=
    # echo "disconnet port ", a.name
    for i, con in v.connections:
        if con.a == a or con.b == a:
            let ai = con.a.connections.find(con.b)
            let bi = con.b.connections.find(con.a)

            if ai >= 0 and bi >= 0:
                con.a.connections.del(ai)
                con.b.connections.del(bi)
                # echo "PORT DISCONNECTeD ", a.name
            v.connections.del(i)
            break

proc portConnected*(v: VSNetworkView, p: VSPortView): VSPortView =
    for con in v.connections:
        if con.a == p: return con.b
        if con.b == p: return con.a

proc onPortDragStart*(v: VSNetworkView, p: VSPortView) =
    if (var con = v.portConnected(p); not con.isNil):
        v.disconnect(p)
        v.dragStartPort = con
        v.dragStartPoint = con.portPinPosition()
        v.dragPosition = p.portPinPosition()
        con.pinColor = pinDragColor
        p.pinColor = pinDefaultColor
    else:
        v.dragStartPort = p
        v.dragPosition = p.frame.origin
        v.dragStartPoint = p.portPinPosition()
        p.pinColor = pinDragColor

    v.setNeedsDisplay()

proc onPortDrag*(v: VSNetworkView, p: Point) =
    v.dragPosition = v.convertPointFromWindow(p)
    v.setNeedsDisplay()

proc onPortDragEnd*(v: VSNetworkView, p: VSPortView) =
    if isPortsCompatible(v.overPort, v.dragStartPort):
        v.connect(v.overPort, v.dragStartPort)

    v.dragStartPort = nil
    v.overPort = nil

    p.pinColor = pinDefaultColor
    v.setNeedsDisplay()

proc onPortOverIn*(v: VSNetworkView, p: VSPortView) =
    if not v.dragStartPort.isNil and p != v.dragStartPort:
        if isPortsCompatible(p, v.dragStartPort):
            p.pinColor = pinConnectOKColor
            v.dragStartPort.pinColor = pinConnectOKColor
            v.overPort = p
        else:
            v.dragStartPort.pinColor = pinConnectErrorColor
            p.pinColor = pinConnectErrorColor

    v.setNeedsDisplay()

proc onPortOverOut*(v: VSNetworkView, p: VSPortView) =
    if p != v.dragStartPort:
        p.pinColor = pinDefaultColor
        if not v.dragStartPort.isNil:
            v.dragStartPort.pinColor = pinDragColor

    v.setNeedsDisplay()
    v.overPort = nil

proc disconnectHost*(v: VSNetworkView, host: VSHostView)=
    for p in host.input:
        v.disconnect(p)

    for p in host.output:
        v.disconnect(p)

proc removeHostVies*(v: VSNetworkView, host: VSHostView)=
    v.disconnectHost(host)
    host.removeFromSuperview()

    # echo "removing ", host.name

proc serialize*(v: VSNetworkView): string =
    var
        templ = "$1\n\n$2\n$3\n$4\n$5\n$6\n"
        dispatchers = ""
        hosts = ""
        links = ""
        flows = ""
        meta = ""

    for h in v.hosts:
        var m = "$1 $2 $3" % [$h.id, $h.frame.x, $h.frame.y]
        meta &= m & "\n"

        var t = "$1 $2" % [$h.id, h.name]
        if h.info.isDispatcher:
            dispatchers &= t & "\n"
        else:
            hosts &= t & "\n"

        if h.info.isLit:
            for i, p in h.output:
                if p.mDefaultValue.len > 0:
                    var lit = "$1.o$2=$3" % [$h.id, $(i-1), p.mDefaultValue]
                    links &= lit & "\n"

        # LINKS
        for ip, p in h.input:
            if p.info.typ != "VSFlow":
                for c in p.connections:
                    let op = c.host.output.find(c) - 1
                    var link = "$1.i$2>$3.o$4" % [$h.id, $(ip-1), $c.host.id, $op]
                    links &= link & "\n"

        # FLOW
        let isFlowHost = h.info.isFlowHost
        for op, p in h.output:
            if p.info.typ == "VSFlow":
                for c in p.connections:
                    if isFlowHost:
                        var sig = "+"
                        if p.name == "false":
                            sig = "-"
                        # for c in p.connections:
                        var flow = "$1>$2$3" % [$h.id, sig, $c.host.id]
                        flows &= flow & "\n"
                    else:
                        var flow = "$1>$2" % [$h.id, $c.host.id]
                        flows &= flow & "\n"

    result = templ % [v.name, dispatchers, hosts, links, flows, meta]

proc deserialize*(v: VSNetworkView, data: seq[string], creator: VSEHostCreator) =
    type NetworkDataState {.pure.} = enum
        name, dispatchers, hosts, links, flow, vsemeta, eof

    var state = NetworkDataState.name
    proc nextState(s: var NetworkDataState)=
        if s != NetworkDataState.eof:
            var si = s.int
            si += 1
            s = si.NetworkDataState

    var hosts = initTable[int, VSHostView]()

    proc extractHost(line: string)=
        try:
            var sline = line.split(" ")
            var id = parseInt(sline[0])
            var host: VSHostView
            for di in vsDispatchersInMeta():
                if di.name == sline[1]:
                    host = creator(di)
                    break

            if host.isNil:
                for hi in vsHostsInMeta():
                    echo "find host ", sline[1], " ?? ", hi.name
                    if hi.name == sline[1]:
                        host = creator(hi)
                        break

            if not host.isNil:
                hosts[id] = host
            else:
                echo "host not created ", line
        except:
            echo "FAILED: extracting host >>", line, "<<"

    proc linkHosts(line: string) =
        for sep in [">", "="]:
            if line.find(sep) > 0:
                var sline = line.split(sep)
                var i = sline[0].split(".")
                var iid = i[0].parseInt()
                var ip = i[1][1 .. ^1].parseInt() + 1

                var ih = hosts.getOrDefault(iid)
                if ih.isNil:
                    echo "LINKAGE FAILED >>", line, "<<"
                    continue


                if sep == "=":
                    ih.output[ip].mDefaultValue = sline[1]
                else:
                    var o = sline[1].split(".")
                    var oid = o[0].parseInt()
                    # echo "output ", o, " oid ", oid
                    var op = o[1][1 .. ^1].parseInt() + 1

                    var oh = hosts.getOrDefault(oid)
                    # echo "link ", ip, " >> ", op, " line ", line, " hosts ", @[ih.info, oh.info]
                    v.connect(ih.input[ip], oh.output[op])

    proc linkFlow(line:string)=
        var sline = line.split(">")
        if sline[1][0] in "+-": #if statement
            var iid = sline[0].parseInt()
            var ih = hosts.getOrDefault(iid)
            let ip = (sline[1][0] == '-').int
            var oid = sline[1][1 .. ^1].parseInt()
            var oh = hosts.getOrDefault(oid)
            if not ih.isNil and not oh.isNil:
                v.connect(ih.output[ip], oh.input[0])
        else:
            var iid = sline[0].parseInt()
            var oid = sline[1].parseInt()
            var ih = hosts.getOrDefault(iid)
            var oh = hosts.getOrDefault(oid)
            if not ih.isNil and not oh.isNil:
                v.connect(ih.output[0], oh.input[0])

    proc readMeta(line: string)=
        var sline = line.split(" ")
        let id = sline[0].parseInt()
        let x = sline[1].parseFloat()
        let y = sline[2].parseFloat()
        let h = hosts.getOrDefault(id)
        if not h.isNil:
            h.setFrameOrigin(newPoint(x, y))

    for line in data:
        var line = line
        if line.len == 0:
            state.nextState
            continue

        case state:
        of NetworkDataState.name:
            v.name = line
        of NetworkDataState.dispatchers, NetworkDataState.hosts:
            extractHost(line)
        of NetworkDataState.links:
            linkHosts(line)
        of NetworkDataState.flow:
            linkFlow(line)
        of NetworkDataState.vsemeta:
            readMeta(line)
        else:
            echo "EOF VSN"
            break

method init*(v: VSNetworkView, r: Rect) =
    procCall v.View.init(r)

    v.connections = @[]
    v.hosts = @[]

    v.portsListner = new(VSPortListner)
    v.portsListner.onPortDrag = proc(p: Point) =
        v.onPortDrag(p)

    v.portsListner.onPortDragEnd = proc(p: VSPortView) =
        v.onPortDragEnd(p)

    v.portsListner.onPortDragStart = proc(p: VSPortView) =
        v.onPortDragStart(p)

    v.portsListner.onPortOverIn = proc(p: VSPortView) =
        v.onPortOverIn(p)

    v.portsListner.onPortOverOut = proc(p: VSPortView) =
        v.onPortOverOut(p)

    v.networkContent = newView(newRect(0.0, 0.0, r.width, r.height))
    v.networkContent.autoresizingMask = {afFlexibleWidth, afFlexibleHeight}

    var networkScroll = newScrollView(v.networkContent)
    v.addSubview(v.networkContent)

proc drawConLine(p1, p2: Point)=
    let a = p1
    let b = p2
    let off = newPoint(min(max(abs(a.x - b.x)*0.5, 40.0), 200), 0.0)
    let aa = p1 - off
    let bb = p2 + off
    currentContext().drawBezier(a, aa, bb, b)

method draw*(v: VSNetworkView, r: Rect)=
    procCall v.View.draw(r)
    # echo "draw network"
    if not v.dragStartPort.isNil:
        currentContext().strokeColor = lineDragColor
        currentContext().strokeWidth = 3.0

        let a = v.dragStartPoint
        let b = v.dragPosition

        if not v.dragStartPort.orientation:
            drawConLine(a, b)
        else:
            drawConLine(b, a)

    if v.connections.len > 0:

        currentContext().strokeWidth = 10.0
        for con in v.connections:
            currentContext().strokeColor = colorForType(con.a.info.typ)
            let a = con.a.portPinPosition
            let b = con.b.portPinPosition
            drawConLine(a, b)
