import vse_types
import vse_port
import sequtils, strutils

import nimx / [
    types, view, button, text_field, panel_view, context, event,
    view_dragging_listener, font, formatted_text, gesture_detector
]

method init*(v: VSHostView, r: Rect)=
    procCall v.View.init(r)

    v.enableDraggingByBackground()

proc hostSize*(info: HostInfo, offw: float = 0.0): tuple[size: Size, portSize: Size]=
    var tis = defaultFont.sizeOfString(info.name)

    var ips = newSize(0.0, 0.0)
    if info.inputPorts.len > 0:
        for i in info.inputPorts:
            var s = defaultFont.sizeOfString(i.name) + pinSize
            ips = newSize(max(ips.width, s.width),0.0)

    var ops = newSize(0.0, 0.0)
    if info.outputPorts.len > 0:
        for i in info.outputPorts:
            var s = defaultFont.sizeOfString(i.name) + pinSize

            ops = newSize(max(ops.width, s.width),0.0)

    var w = max(
            tis.width,
            max(ops.width, ips.width) * 2
        ) + offw

    var h = 25.0 + portStep * max(info.inputPorts.len, info.outputPorts.len).float

    result.size = newSize(w,h)
    result.portSize = newSize(max(ops.width, ips.width), 25.0)

proc createHostView*(info: HostInfo, listner: VSPortListner): VSHostView=
    result.new()
    result.collapsible = false
    result.name = info.name
    result.info = info

    let sizeI = info.hostSize(30.0)
    let size = sizeI.size

    result.init(newRect(50, 50, size.width, size.height))
    result.backgroundColor.a = 0.75

    let lb = newLabel(result, newPoint(0,0), newSize(size.width, 20), info.name)
    lb.formattedText.horizontalAlignment = haCenter
    lb.backgroundColor = newColor(0.5, 0.5, 0.5, 0.75)
    lb.textColor = whiteColor()

    var inputViews = newSeq[VSPortView]()
    var ip = newPoint(0.0, 25.0)
    if info.inputPorts.len > 0:
        for pi in info.inputPorts:
            var port = createPortView(pi, ip, sizeI.portSize, false)
            inputViews.add(port)

    var outputViews = newSeq[VSPortView]()

    var op = newPoint(size.width - sizeI.portSize.width, 25.0)
    if info.outputPorts.len > 0:
        for pi in info.outputPorts:
            var port = createPortView(pi, op, sizeI.portSize, true)
            outputViews.add(port)
    
    result.input = @[]
    for i, p in inputViews:
        var list = new(PortViewScrollListner)
        list.port = p
        p.addGestureDetector(newScrollGestureDetector(list))
        p.listner = listner
        p.host = result
        result.addSubview(p)
        result.input.add(p)

    result.output = @[]
    for i, p in outputViews:
        var list = new(PortViewScrollListner)
        list.port = p
        p.addGestureDetector(newScrollGestureDetector(list))
        p.listner = listner
        p.host = result
        result.addSubview(p)        
        result.output.add(p)

proc serialize*(h: VSHostView): string = 
    result = "$1 $2" % [$h.id, h.info.name]
    for i, p in h.input:
        if p.info.typ == VSFLOWTYPE: 
            continue

        if not p.connections.isNil:
            for con in p.connections:
                result &= "\n"
                result &= "$1.$2>$3.$4" % [$h.id, "i" & $(h.input.find(p)+1), $con.host.id, "o" & $(con.host.output.find(con)+1)]
