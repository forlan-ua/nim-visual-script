import strutils, tables, strutils, typetraits, variant, parseutils

import .. / visual_script

type Node = ref object of RootObj
proc findNode(parent: Node, nodeName: string): Node {.vsHost.} = echo "findNode: ", nodeName
proc getRootNode(): Node {.vsHost.} = echo "getRootNode"
type Component = ref object of RootObj
proc getComponent(node: Node): Component {.vsHost.} = echo "getComponent"
proc setText(component: Component, text: string) {.vsHost.} = echo "setText: ", text
proc addChild(parent: Node, child: Node) {.vsHost.} = echo "addChild"


const source1 = """
MyNetwork1

10 TestDispatcher1
11 TestDispatcher2

0 GetRootNodeVSHost
5 EqStringVSHost
6 StringLitVSHost
1 FindNodeVSHost
2 GetComponentVSHost
3 SetTextVSHost
4 AddChildVSHost
8 IfVSHost

1.i1>10.o0
1.i0>0.o0
2.i0>1.o0
3.i0>2.o0
3.i1>10.o1
4.i0>1.o0
4.i1>10.o2
5.i0>10.o0
5.i1>6.o0
8.i0>5.o0
6.o0=test1

10>1
1>8
8>+2
8>-4
2>3

###
"""

const source2 = """
MyNetwork2

10 TestDispatcher3
11 TestDispatcher4

0 GetRootNodeVSHost
5 EqStringVSHost
6 StringLitVSHost
1 FindNodeVSHost
2 GetComponentVSHost
3 SetTextVSHost
4 AddChildVSHost
8 IfVSHost

1.i1>10.o0
1.i0>0.o0
2.i0>1.o0
3.i0>2.o0
3.i1>10.o1
4.i0>1.o0
4.i1>10.o2
5.i0>10.o0
5.i1>6.o0
6.o0=test1
8.i0>5.o0

10>1
1>2
2>3
2>4

###
"""

var n = Node.new()

generateNetwork(source1)

registerNetworkDispatcher("TestDispatcher1", {nodeName: string, text: string, child: Node})

echo " "
dispatchNetwork("TestDispatcher1", "test1", "test2", n)
echo " "
dispatchNetwork("TestDispatcher1", "test3", "test4", n)

# dispatchNetwork_TestDispatcher1("test1", "test3", n)

echo " "
for d in eachDispatcher():
    echo d.ports
