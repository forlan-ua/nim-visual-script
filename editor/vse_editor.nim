
import nimx / [
    types, view, button, text_field, panel_view, context, event,
    view_dragging_listener, font, formatted_text, gesture_detector
]

import vse_types
export vse_types
import vse_colors
import vse_host
import vse_port

proc connect*(v: VSNetworkView, a, b: VSPortView)=
    if a.connections.isNil:
        a.connections = @[]

    if b.connections.isNil:
        b.connections = @[]

    if v.connections.isNil:
        v.connections = @[]

    if a notin b.connections and b notin a.connections:
        a.connections.add(b)
        b.connections.add(a)
        if not a.orientation:
            v.connections.add((a: a, b: b))
        else:
            v.connections.add((a: b, b: a))

proc disconnect*(v: VSNetworkView, a: VSPortView)=
    for i, con in v.connections:
        if con.a == a or con.b == a:
            let ai = con.a.connections.find(con.b)
            let bi = con.b.connections.find(con.a)

            if ai >= 0 and bi >= 0:
                con.a.connections.del(ai)
                con.b.connections.del(bi)
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
    v.dragPosition = p
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

method init*(v: VSNetworkView, r: Rect) =
    procCall v.View.init(r)

    v.connections = @[]

    let portListner = new(VSPortListner)
    portListner.onPortDrag = proc(p: Point) =
        v.onPortDrag(p)

    portListner.onPortDragEnd = proc(p: VSPortView) =
        v.onPortDragEnd(p)

    portListner.onPortDragStart = proc(p: VSPortView) =
        v.onPortDragStart(p)

    portListner.onPortOverIn = proc(p: VSPortView) =
        v.onPortOverIn(p)

    portListner.onPortOverOut = proc(p: VSPortView) =
        v.onPortOverOut(p)

    var eventHostInfo: HostInfo
    eventHostInfo.name = "VSEvent"

    eventHostInfo.inputPorts = @[]
    eventHostInfo.inputPorts.add((name: "In1", typ: "int", value: "hello!", active: false))
    # eventHostInfo.inputPorts.add((name: "In2", typ: "string", value: "hello!", active: false))

    eventHostInfo.outputPorts = @[]
    eventHostInfo.outputPorts.add((name: "EventOfSomeFuckingShitHappens", typ: "string", value: "hello!", active: true))
    eventHostInfo.outputPorts.add((name: "Reward", typ: "bool", value: "World", active: true))

    var hv = createHostView(eventHostInfo, portListner)
    v.addSubview(hv)

    for i in 0 .. 4:
        var otherHostInfo: HostInfo
        otherHostInfo.name = "Action" & $i
        otherHostInfo.inputPorts = @[]
        otherHostInfo.inputPorts.add((name: "In1", typ: "int", value: "hello!", active: false))
        otherHostInfo.inputPorts.add((name: "In2", typ: "bool", value: "hello!", active: false))

        otherHostInfo.outputPorts = @[]
        # otherHostInfo.outputPorts.add((name: "Out1", typ: "bool", value: "hello!", active: true))
        # otherHostInfo.outputPorts.add((name: "Out2", typ: "char", value: "hello!", active: true))
        otherHostInfo.outputPorts.add((name: "Out3", typ: "int", value: "hello!", active: true))

        hv = createHostView(otherHostInfo, portListner)
        v.addSubview(hv)

proc drawConLine(p1, p2: Point)=
    let a = p1
    let b = p2
    let off = newPoint(min(abs(a.x - b.x), 200), 0.0)
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



