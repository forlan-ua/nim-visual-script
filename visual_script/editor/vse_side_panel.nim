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
import vse_metadata_cache

type VSSidePanelView* = ref object of View
    onHostAdd*: VSEHostCreator
    onChanged*: proc()
    # hostMetaCache: seq[VSHostMeta]
    # dispatcherCache: seq[DispatcherMeta]
    filter: TextField
    content: View

proc createRegisteredHostView(r: Rect, name: string, cb: proc()): View =
    result = newView(r)
    discard newLabel(result, newPoint(0,0), newSize(r.width, 20.0), name)
    var btn = newButton(newRect(0, 25.0, 40.0, 20.0))
    btn.title = "Add"
    btn.onAction do():
        echo "cb1 ", name
        cb()
    result.addSubview(btn)
    result.backgroundColor = newColor(0.5,0.5,0.5, 0.96)

proc onItemClick[T](v: VSSidePanelView, info: T): proc()=
    result = proc()=
        echo "cb 2 ", info.name
        if not v.onHostAdd.isNil:
            echo "cb 3 ", info.name
            discard v.onHostAdd(info)

proc clearContent(v: VSSidePanelView)=
    while v.content.subviews.len > 0:
        v.content.subviews[0].removeFromSuperView()

proc loadHosts(v: VSSidePanelView)=
    v.clearContent()
    for info in vsHostsInMeta():
        if v.filter.text.len == 0 or (v.filter.text.toLowerAscii in info.name.toLowerAscii):
            var h = createRegisteredHostView(newRect(0, 0, v.frame.width, 60), info.name, v.onItemClick(info))
            v.content.addSubview(h)
    v.setNeedsDisplay()

proc loadDispatchers(v: VSSidePanelView)=
    v.clearContent()
    for info in vsDispatchersInMeta():
        if v.filter.text.len == 0 or (v.filter.text.toLowerAscii in info.name):
            var h = createRegisteredHostView(newRect(0, 0, v.frame.width, 60), info.name, v.onItemClick(info))
            v.content.addSubview(h)

proc createSidePanel*(r: Rect): VSSidePanelView=
    let v = new(VSSidePanelView, r)
    v.autoresizingMask = { afFlexibleMaxX, afFlexibleHeight }

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
    scroll.autoresizingMask = { afFlexibleMaxX, afFlexibleHeight }
    scroll.contentView = newStackView(zeroRect)
    scroll.contentView.autoresizingMask = { afFlexibleMaxX, afFlexibleHeight }
    v.addSubview(scroll)

    v.content = scroll.contentView

    v.onChanged()

    result = v
