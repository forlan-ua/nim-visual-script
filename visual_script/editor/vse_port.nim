import vse_types, vse_colors

import nimx / [
    types, view, button, text_field, panel_view, context, event,
    view_dragging_listener, font, formatted_text, gesture_detector
]

proc portPinPosition*(p: VSPortView): Point=
    let pinc = newPoint(pinSize.width * 0.5, pinSize.height * 0.5)
    result = p.superview.frame.origin + p.pinPosition + pinc + p.frame.origin

proc isPortsCompatible*(a, b: VSPortView): bool =
    if a.isNil or b.isNil: return false
    result = a.info.typ == b.info.typ and
        a.info.active != b.info.active and
        a.superview != b.superview

method onTapDown(ls: PortViewScrollListner, e: var Event) =
    ls.port.listner.onPortDragStart(ls.port)

method onScrollProgress(ls: PortViewScrollListner, dx, dy : float32, e : var Event) =
    ls.port.listner.onPortDrag(e.position)

method onTapUp*(ls: PortViewScrollListner, dx, dy : float32, e : var Event) =
    ls.port.listner.onPortDragEnd(ls.port)

method onMouseIn*(v: VSPortView, e: var Event) =
    v.listner.onPortOverIn(v)

method onMouseOut*(v: VSPortView, e: var Event) =
    v.listner.onPortOverOut(v)

method draw*(v: VSPortView, rect: Rect)=
    procCall v.View.draw(rect)

    var r: Rect
    r.origin.x = v.pinPosition.x
    r.origin.y = v.pinPosition.y
    r.size.width = pinSize.width
    r.size.height = pinSize.height

    let c = currentContext()

    if v.isFlow:
        c.strokeColor = flowColor
        c.fillColor = flowColor
    else:
        if v.connections.len > 0:
            c.strokeColor = pinConnectedColor
            c.fillColor = pinConnectedColor
        else:
            c.strokeColor = v.pinColor
            c.fillColor = pinDefaultColor

    c.strokeWidth = 5.0
    c.drawEllipseInRect(r)

proc createPortView*(info: PortInfo, p: var Point, s: Size, orientation: bool): VSPortView=
    result.new()
    result.name = info.name
    result.orientation = orientation
    result.pinColor = pinDefaultColor
    result.info = info

    result.trackMouseOver(true)

    result.init(newRect(p.x, p.y, s.width, s.height))

    result.pinPosition = newPoint((if orientation: s.width - pinSize.width * 0.5 else: -pinSize.width * 0.5), 0)

    var x = pinSize.width
    if orientation:
        x = 0.0

    var lb = newLabel(result, newPoint(x, 0.0), newSize(s.width - pinSize.width, s.height), info.name)
    lb.font = defaultFont
    lb.textColor = colorForType(info.typ)

    p.y = p.y + portStep


