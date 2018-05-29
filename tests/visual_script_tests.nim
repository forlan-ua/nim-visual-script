import strutils, tables, strutils, typetraits, variant, parseutils

import visual_script

type Node = ref object of RootObj
proc findNode(parent: Node, nodeName: string): Node {.vsHost.} = echo "findNode: ", nodeName
proc getRootNode(): Node {.vsHost.} = echo "getRootNode"
type Component = ref object of RootObj
proc getComponent(node: Node): Component {.vsHost.} = echo "getComponent" 
proc setText(component: Component, text: string) {.vsHost.} = echo "setText: ", text
proc addChild(parent: Node, child: Node) {.vsHost.} = echo "addChild"


const source1 = """
MyNetwork1>TestDispatcher

0 GetRootNodeVSHost

1 FindNodeVSHost
1.i1>i0
1.i0>0.o0

2 GetComponentVSHost
2.i0>1.o0

3 SetTextVSHost
3.i0>2.o0
3.i1>i1

4 AddChildVSHost
4.i0>1.o0
4.i1>i2

3>4
"""

const source2 = """
MyNetwork2>TestDispatcher

0 GetRootNodeVSHost

1 FindNodeVSHost
1.i1>i0
1.i0>0.o0

2 GetComponentVSHost
2.i0>1.o0

3 SetTextVSHost
3.i0>2.o0
3.i1>i1

4 AddChildVSHost
4.i0>1.o0
4.i1>i2

1>2>3>4
"""

var n = Node.new()

generateNetwork(source1)
generateNetwork(source2)

dispatchNetwork("TestDispatcher", "test1", "test2", n)