import nimx / [
    types, view, button, text_field, stack_view,
    font, formatted_text, segmented_control,
    scroll_view
]

import algorithm

import visual_script.vs_host
import visual_script.vs_network
import visual_script.vs_std

import vse_types

type VSSidePanelView* = ref object of View
    onHostAdd*: proc(meta: HostInfo)
    onChanged: proc()
    hostMetaCache: seq[VSHostMeta]
    dispatcherCache: seq[DispatcherMeta]
    filter: TextField
    content: View

proc metaToInfo(meta: VSHostMeta): HostInfo=
    var info: HostInfo
    info.name = meta.typeName
    info.inputPorts = @[]
    info.inputPorts.add((name:"Input", typ:VSFLOWTYPE, value:"", active: false))
    if meta.inputs.len > 0:
        for i in meta.inputs:
            info.inputPorts.add((name: i.name, typ: i.sign, value: i.default, active: false))

    info.outputPorts = @[]
    info.outputPorts.add((name:"Output", typ:VSFLOWTYPE, value:"", active: true))
    if meta.outputs.len > 0:
        for i in meta.outputs:
            info.outputPorts.add((name: i.name, typ: i.sign, value: i.default, active: true))

    result = info

proc metaToInfo(meta: DispatcherMeta): HostInfo=
    var info: HostInfo
    info.name = meta.name
    info.inputPorts = @[]

    info.outputPorts = @[]
    info.outputPorts.add((name:"Output", typ:VSFLOWTYPE, value:"", active: true))
    if meta.ports.len > 0:
        for i in meta.ports:
            info.outputPorts.add((name: i.name, typ: i.sign, value: "", active: true))

    result = info
    echo "MetaToInfo dispatcher ", meta, " info ", info

proc createRegisteredHostView(r: Rect, name: string, cb: proc()): View =
    result = newView(r)
    discard newLabel(result, newPoint(0,0), newSize(r.width, 20.0), name)
    var btn = newButton(newRect(0, 25.0, 40.0, 20.0))
    btn.title = "Add"
    btn.onAction do():
        cb()
    result.addSubview(btn)
    result.backgroundColor = newColor(0.5,0.5,0.5, 0.96)

proc onItemClick[T](v: VSSidePanelView, meta: T): proc()=
    let meta = meta
    let info = meta.metaToInfo()
    result = proc()=
        if not v.onHostAdd.isNil:
            v.onHostAdd(info)

proc clearContent(v: VSSidePanelView)=
    while v.content.subviews.len > 0:
        v.content.subviews[0].removeFromSuperView()

proc loadHosts(v: VSSidePanelView)=
    v.clearContent()
    v.hostMetaCache.sort do(a,b:VSHostMeta) -> int:
        result = cmp(a.typeName, b.typeName)
    for i, meta in v.hostMetaCache:
        if v.filter.text.len == 0 or (v.filter.text.toLowerAscii in meta.typeName.toLowerAscii):
            var h = createRegisteredHostView(newRect(0, 0, v.frame.width, 60), meta.typeName, v.onItemClick(meta))
            v.content.addSubview(h)
    v.setNeedsDisplay()

proc loadDispatchers(v: VSSidePanelView)=
    v.clearContent()
    v.dispatcherCache.sort do(a,b: DispatcherMeta) -> int:
        result = cmp(a.name, b.name)
    for i, meta in v.dispatcherCache:
        if v.filter.text.len == 0 or (v.filter.text.toLowerAscii in meta.name.toLowerAscii):
            var h = createRegisteredHostView(newRect(0, 0, v.frame.width, 60), meta.name, v.onItemClick(meta))
            v.content.addSubview(h)

proc createSidePanel*(r: Rect): VSSidePanelView=
    let v = new(VSSidePanelView, r)

    v.hostMetaCache = @[]
    for host in walkHostRegistry():
        v.hostMetaCache.add(host.metadata)

    v.dispatcherCache = @[]
    for disp in eachDispatcher():
        v.dispatcherCache.add(disp.metadata)

    let sc = SegmentedControl.new(newRect(0, 0, r.width, 22))
    sc.segments = @["Hosts", "Dispatchers"]
    sc.autoresizingMask = { afFlexibleWidth, afFlexibleMaxY }
    sc.onAction do():
        v.onChanged()

    v.addSubview(sc)

    let tf = newTextField(newRect(0,25,r.width, 22))
    tf.continuous = true
    tf.onAction do():
        v.onChanged()
    v.addSubview(tf)
    v.filter = tf

    v.onChanged = proc()=
        if sc.selectedSegment == 0:
            v.loadHosts()
        else:
            v.loadDispatchers()

    var scroll = newScrollView(newRect(0, 50, r.width, r.height - 50))
    scroll.contentView = newStackView(zeroRect)
    v.addSubview(scroll)

    v.content = scroll.contentView

    v.loadHosts()

    result = v
