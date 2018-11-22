
import nimx / [
    types, view, button, text_field, panel_view, context, event,
    view_dragging_listener, font, formatted_text, gesture_detector,
    scroll_view, editor / tab_view
]

import os_files.dialog

import visual_script.vs_host
import visual_script.vs_std

import vse_side_panel
import vse_types
export vse_types
import vse_colors
import vse_host
import vse_port
import vse_menu_panel
import vse_network

proc newNetworkView(r: Rect, data:string = ""): VSNetworkView=
    result.new()
    result.init(r)
    if data.len > 0:
        result.deserialize(data)

proc addNetworkView(v: VSEditorView, nv: VSNetworkView)=
    if nv.name notin v.networks:
        v.networks[nv.name] = nv
        v.networksSuperView.TabView.addTab(nv.name, nv)

proc networkRect(v: VSEditorView):Rect = newRect(0.0, 0.0, v.bounds.width - 200.0, v.bounds.height - 20.0)

method init*(v: VSEditorView, r:Rect)=
    procCall v.View.init(r)
    v.backgroundColor = whiteColor()
    v.networks = initTable[string, VSNetworkView]()

    var networksView = new(TabView, newRect(200.0, 20.0, r.width - 200.0, r.height - 20.0))
    v.addSubview(networksView)
    v.networksSuperView = networksView

    var emptyNetwork = newNetworkView(v.networkRect)
    emptyNetwork.name = "Empty"
    v.addNetworkView(emptyNetwork)
    v.currentNetwork = emptyNetwork

    var sidePanel = createSidePanel(newRect(0.0, 20.0, 200.0, r.height - 20.0))
    v.addSubview(sidePanel)
    sidePanel.onHostAdd = proc(info: HostInfo)=
        let cn = v.currentNetwork

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

    # var registryView = newView(newRect(0,20, 200, r.height))
    # registryView.backgroundColor = newColor(0.7, 0.7, 0.7, 1.0)
    # var y = 0.0

    # for host in walkHostRegistry():
    #     echo "host ", host.name , " metadata ", host.metadata
    #     let rv = createRegisteredHostView(newRect(0, y, 200.0, 60.0), host.metadata.typeName, v.currentNetwork.onAddHostView(host))
    #     registryView.addSubview(rv)
    #     y += 65.0

    # var scroll = newScrollView(registryView)
    # v.addSubview(scroll)

    var panel = createVSMenu(newRect(0.0, 0.0, r.width, 20.0))
    v.addSubview(panel)

    panel.addMenuWithHandler("File/Load") do():
        var di: DialogInfo
        di.kind = dkOpenFile
        di.title = "Open VSNetwork"
        di.filters = @[(name: "VSNetwork", ext: "*.vsn")]
        let path = di.show()
        if path.len > 0:
            var data = readFile(path)
            var nv = newNetworkView(v.networkRect, data)
            v.addNetworkView(nv)
            echo "load network ", data

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

    panel.addMenuWithHandler("View/Registry") do():
        echo "toggle registry"

    panel.addMenuWithHandler("View/Some/Test") do():
        echo "sas"

    panel.addMenuWithHandler("About/WTF") do():
        echo "wtf"
