
import nimx / [
    types, view, button, text_field, panel_view, context, event,
    view_dragging_listener, font, formatted_text, gesture_detector,
    scroll_view, editor / tab_view
]

import os_files / dialog
import visual_script / [ vs_std, vs_host, vs_network ]
import visual_script / runtime / main_dispatcher
import tables

import vse_types
export vse_types

import vse_side_panel
import vse_colors
import vse_host
import vse_port
import vse_menu_panel
import vse_network
import vse_metadata_cache
import vse_popup

proc addNetworkView(v: VSEditorView, nv: VSNetworkView)=
    # var old = v.networks.getOrDefault(nv.name)
    if nv.name notin v.networks:
        v.networks[nv.name] = nv
        v.networksSuperView.TabView.addTab(nv.name, nv)

proc networkRect(v: VSEditorView):Rect = v.bounds

proc hostCreator(v: VSEditorView): VSEHostCreator=
    result = proc(info: HostInfo): VSHostView=
        let cn = v.currentNetwork

        echo "creator called ", info

        var hostV = createHostView(info, cn.portsListner)
        hostV.setFrameOrigin(newPoint(400,400))
        var remHostBtn = newButton(newRect(hostV.frame.size.width - 20.0, 1.0, 20.0, 20.0))
        remHostBtn.title = "x"
        remHostBtn.onAction do():
            let index = cn.hosts.find(hostV)
            if index > -1:
                cn.removeHostVies(cn.hosts[index])
                cn.hosts.del(index)
            echo "try remove hostV ", hostV.name

        hostV.addSubview(remHostBtn)

        hostV.id = cn.currHostID
        inc cn.currHostID

        cn.networkContent.addSubview(hostV)
        cn.hosts.add(hostV)
        result = hostV

proc selectCurrentTab(v: VSEditorView)=
    let ti = v.networksSuperView.TabView.tabIndex(v.currentNetwork)
    if ti >= 0:
        v.networksSuperView.TabView.selectTab(ti)

# proc runNetwork(v: VSEditorView)=
#     let source = v.currentNetwork.serialize
#     echo "run script ", source
#     var network = generateNetwork(source)
#     if network.flows.len > 0:
#         for k, flow in network.flows:
#             flow.run()
            # echo "name ", host.name
        # echo "name ", network.hosts[0].name
        # network.hosts[0].invokeFlow()

proc runNetwork(v: VSEditorView) =
    let source = v.currentNetwork.serialize
    var network = generateNetwork(source)
    let args = @["test", "1", "5.5"]
    dispatchNetwork("main", args, args.len)

method init*(v: VSEditorView, r:Rect)=
    procCall v.View.init(r)
    v.backgroundColor = whiteColor()
    v.networks = initTable[string, VSNetworkView]()

    var networksView = new(TabView, newRect(200.0, 20.0, r.width - 200.0, r.height - 20.0))
    networksView.autoResizingMask = {afFlexibleWidth, afFlexibleHeight}
    v.addSubview(networksView)
    v.networksSuperView = networksView

    var emptyNetwork = new(VSNetworkView, networksView.bounds)
    emptyNetwork.name = "Empty"
    emptyNetwork.autoResizingMask = {afFlexibleWidth, afFlexibleHeight}
    v.addNetworkView(emptyNetwork)
    v.currentNetwork = emptyNetwork

    var sidePanel = createSidePanel(newRect(0.0, 20.0, 200.0, r.height - 20.0))
    sidePanel.autoResizingMask = {afFlexibleHeight}
    sidePanel.onHostAdd = v.hostCreator()
    v.addSubview(sidePanel)

    var panel = createVSMenu(newRect(0.0, 0.0, r.width, 20.0))
    panel.autoResizingMask = {afFlexibleWidth}
    v.addSubview(panel)

    panel.addMenuWithHandler("File/Load") do():
        var di: DialogInfo
        di.kind = dkOpenFile
        di.title = "Open VSNetwork"
        di.filters = @[(name: "VSNetwork", ext: "*.vsn")]
        let path = di.show()
        if path.len > 0:
            reloadCache()
            var data = readFile(path)
            if data.len > 0:
                var data = data.splitLines()
                var nv = new(VSNetworkView, networksView.bounds)
                nv.autoResizingMask = {afFlexibleWidth, afFlexibleHeight}
                nv.name = data[0]
                v.currentNetwork = nv
                v.addNetworkView(nv)
                nv.deserialize(data, v.hostCreator())
                v.selectCurrentTab()

    panel.addMenuWithHandler("File/Save") do():
        var di: DialogInfo
        di.kind = dkSaveFile
        di.title = "Save VSNetrowk as ..."
        di.filters = @[(name: "VSNetwork", ext: "*.vsn")]
        di.extension = "vsn"
        let path = di.show()
        if path.len > 0:
            writeFile(path, v.currentNetwork.serialize)
            echo "save to ", path

    panel.addMenuWithHandler("Network/New") do():
        var emptyNetwork = new(VSNetworkView, networksView.bounds)
        emptyNetwork.name = "Empty"
        emptyNetwork.autoResizingMask = {afFlexibleWidth, afFlexibleHeight}
        v.currentNetwork = emptyNetwork
        v.addNetworkView(emptyNetwork)
        v.selectCurrentTab()

    panel.addMenuWithHandler("Network/Reload Cache") do():
        reloadCache()
        sidePanel.onChanged()

    panel.addMenuWithHandler("Network/Rename") do():
        let ti = v.networksSuperView.TabView.tabIndex(v.currentNetwork.name)
        if ti >= 0:
            let oldName = v.currentNetwork.name
            v.newTfPopup(continuous = false) do(str: string):
                v.currentNetwork.name = str
                v.networksSuperView.TabView.setTitleOfTab(str, ti)
                v.networks[oldName] = nil
                v.networks[str] = v.currentNetwork

    panel.addMenuWithHandler("Network/Close") do():
        var tc = v.networksSuperView.TabView.tabIndex(v.currentNetwork)
        if tc > 0:
            v.networksSuperView.TabView.removeTab(tc)
            v.currentNetwork = v.networksSuperView.TabView.selectedView().VSNetworkView

    panel.addMenuWithHandler("Network/Copy") do():
        var data = v.currentNetwork.serialize().splitLines()
        var nv = new(VSNetworkView, networksView.bounds)
        nv.autoResizingMask = {afFlexibleWidth, afFlexibleHeight}
        nv.name = data[0] & "_copy"
        v.currentNetwork = nv
        v.addNetworkView(nv)
        nv.deserialize(data, v.hostCreator())
        v.selectCurrentTab()

    panel.addMenuWithHandler("View/Registry") do():
        echo "toggle registry"

    panel.addMenuWithHandler("View/Some/Test") do():
        echo "sas"

    panel.addMenuWithHandler("Network/Run") do():
        v.runNetwork()
