import algorithm, tables
import visual_script/[ vs_host, vs_network, vs_std]
import vse_types

proc metaToInfo*(meta: VSHostMeta): HostInfo=
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

proc metaToInfo*(meta: DispatcherMeta): HostInfo=
    var info: HostInfo
    info.name = meta.name
    info.inputPorts = @[]

    info.outputPorts = @[]
    info.outputPorts.add((name:"Output", typ:VSFLOWTYPE, value:"", active: true))
    if meta.ports.len > 0:
        for i in meta.ports:
            info.outputPorts.add((name: i.name, typ: i.sign, value: "", active: true))

    info.isDispatcher = true

    result = info

var metaCache:Table[string, HostInfo]

proc reloadCache*()=
    metaCache = initTable[string, HostInfo]()
    for host in walkHostRegistry():
        let hi = metaToInfo(host.metadata)
        metaCache[hi.name] = hi

    for disp in eachDispatcher():
        let di = metaToInfo(disp.metadata)
        metaCache[di.name] = di

    # echo "\n\nprintcache\n\n"
    # for k,v in metaCache:
    #     echo k, " >> ", v, " \n"
    # echo "\n\END\n\n"
reloadCache()

iterator vsHostsInMeta*(): HostInfo=
    for k, v in metaCache:
        if not v.isDispatcher:
            yield v

iterator vsDispatchersInMeta*(): HostInfo=
    for k, v in metaCache:
        if v.isDispatcher:
            yield v
