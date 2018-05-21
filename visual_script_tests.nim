import strutils, tables, strutils, typetraits

import vs_types

type Node = ref object of RootObj
proc findNode(parent: Node, nodeName: string): Node {.vsHost.} = echo "findNode: ", nodeName
proc getRootNode(): Node {.vsHost.} = echo "getRootNode"
type Component = ref object of RootObj
proc getComponent(node: Node): Component {.vsHost.} = echo "getComponent" 
proc setText(component: Component, text: string) {.vsHost.} = echo "setText: ", text
proc addChild(parent: Node, child: Node) {.vsHost.} = echo "addChild"

proc accessPoint(): tuple[nodeName, text: string, child: Node] {.vsHost.} =
    discard


let network = VSNetwork.new()
network.hosts = newSeq[VSHost](5)

let h0 = getHostFromRegistry(AccessPointVSHost)
h0.nodeName.readImpl = proc(): string =
    return h0.nodeName.rawData()
h0.text.readImpl = proc(): string =
    return h0.text.rawData()
h0.child.readImpl = proc(): Node =
    return h0.child.rawData()

let h1 = getHostFromRegistry(GetRootNodeVSHost)
network.hosts[0] = h1

let h2 = getHostFromRegistry(FindNodeVSHost)
h2.nodeName.connect(h0.nodeName)
h2.parent.connect(h1.output)
network.hosts[1] = h2

let h3 = getHostFromRegistry(GetComponentVSHost)
h3.node.connect(h2.output)
network.hosts[2] = h3

let h4 = getHostFromRegistry(SetTextVSHost)
h4.component.connect(h3.output)
h4.text.connect(h0.text)
network.hosts[3] = h4

let h5 = getHostFromRegistry(AddChildVSHost)
h5.parent.connect(h2.output)
h5.child.connect(h0.child)
network.hosts[4] = h1


network.flow = proc() =
    h0.nodeName.write("test1")
    h0.text.write("test2")

    h0.invokeFlow()
    h4.invokeFlow()
    h5.invokeFlow()
echo "\n\nSTART FLOW 1:"
network.flow()

network.clean()

network.flow = proc() =
    h0.nodeName.write("test1")
    h0.text.write("test2")

    h0.invokeFlow()
    h2.invokeFlow()
    h4.invokeFlow()
    h5.invokeFlow()
echo "\n\nSTART FLOW 2:"
network.flow()

network.destroy()


let source = """
0 AccessPointClick

1 GetRootNodeVSHost

2 FindNodeVSHost
2.nodeName->0.nodeName
2.parent->1.output

3 GetComponentVSHost
3.node->2.output

4 SetTextVSHost
4.node->3.output
4.text->0.text

5 AddChildVSHost
5.parent.connect(2.output)
5.child.connect(0.child)

0->4->5

0->2->3->4->5

"""