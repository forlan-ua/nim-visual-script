import macros, strutils


type VSPortKind = enum
    Input
    Output


type VSPort[T] = ref object of RootObj
    name: string
    kind: VSPortKind
    connections: seq[VSPort[T]]
    onUpdate: proc()
    data: T


proc connect(p1: VSPort, p2: varargs[VSPort]) =
    for c in p2:
        if p1.connections.find(c) == -1:
            p1.connections.add(c)

        if c.connections.find(p1) == -1:
            c.connections.add(p1)

        p1.data = c.data

proc disconnect(p1: VSPort, p2: varargs[VSPort]) =
    for c in p2:
        let ind1 = p1.connections.find(c)
        if ind1 > -1:
            p1.connections.del(ind1)

        let ind2 = c.connections.find(p1)
        if ind2 > -1:
            c.connections.del(ind2)

proc deepUpdate(p: VSPort) =
    for c in p.connections:
        if not c.onUpdate.isNil:
            c.onUpdate()

proc write*[T](p: VSPort[T], data: T) =
    p.data = data
    if p.kind == Output:
        for c in p.connections:
            c.data = data
            if not c.onUpdate.isNil:
                c.onUpdate()

proc read*[T](p: VSPort[T]): T =
    result = p.data

proc newVSPort(T: typedesc, kind: VSPortKind): VSPort[T] =
    result.new()
    result.kind = kind
    result.connections = @[]


type VSHost = ref object of RootObj
    name: string

method invoke(h: VSHost) {.base.} = discard

proc listen(h: VSHost, p: VSPort) =
    p.onUpdate =  proc() =
        h.invoke()

####
type Node = ref object
proc newNodeWithResource(s: string): Node = echo "newNodeWithResource: ", s


type OpenWindowAP = ref object of VSHost
    input0: VSPort[Node]
    input1: VSPort[string]
    
    output0: VSPort[Node]
    output1: VSPort[string]

method invoke(ap: OpenWindowAP) =
    ap.output0.write(ap.input0.read())
    ap.output1.write(ap.input1.read())

type NewNodeWithResource = ref object of VSHost
    input0: VSPort[string]
    output0: VSPort[Node]

method invoke(f: NewNodeWithResource) =
    let val = f.input0.read()
    if val.isNil:
        return
    f.output0.write(newNodeWithResource(val))


proc createOpenWindowAPFlow() =
    var rootNode: Node
    var comp: string = "TEST1"

    let d1 = OpenWindowAP.new()
    d1.input0 = newVSPort(Node, Input)
    d1.input0.write(rootNode)
    d1.input1 = newVSPort(string, Input)
    d1.input1.write(comp)
    d1.output0 = newVSPort(Node, Output)
    d1.output1 = newVSPort(string, Output)
    d1.invoke()

    let d2 = NewNodeWithResource.new()
    d2.input0 = newVSPort(string, Input)
    d2.output0 = newVSPort(Node, Output)
    d2.listen(d2.input0)
    d2.input0.connect(d1.output1)
    d2.invoke()

    d1.output1.write("TEST2")

proc getName(n: NimNode): string =
    if n.kind == nnkIdent:
        return $(n.ident)
    elif n.kind == nnkPostfix:
        return $(n[1].ident)

macro vshost(a: untyped): typed =
    case a.kind:
        of nnkProcDef, nnkMethodDef:
            discard
        else:
            error "Unexpected kind. For proc and method only!"
    
    let typeName = ident(a[0].getName().capitalizeAscii() & "VSHost")
    let ftype = nnkTypeSection.newTree(
        nnkTypeDef.newTree(
            nnkPostfix.newTree(
                ident("*"),
                typeName
            ),
            newEmptyNode(),
            nnkObjectTy.newTree(
                newEmptyNode(),
                nnkOfInherit.newTree(
                    ident("VSHost")
                ),
                newEmptyNode()
            )
        )
    )

    let invoke = newProc(
        nnkPostfix.newTree(ident("*"), ident("invoke")), 
        [newEmptyNode(), nnkIdentDefs.newTree(ident("vs"), typeName, newEmptyNode())], 
        nnkStmtList.newTree(nnkDiscardStmt.newTree(newEmptyNode())), 
        nnkMethodDef
    )

    let define = newProc(
        nnkPostfix.newTree(ident("*"), ident("create" & $typeName.ident)),
        [newEmptyNode()],
        nnkStmtList.newTree(nnkDiscardStmt.newTree(newEmptyNode()))
    )

    result = nnkStmtList.newTree(
        ftype,
        invoke,
        define
    )
    result.add(a)

    echo repr(result)


proc canHost(a: int, b: Node, c: proc(), d: string = "asd", e: proc() = nil): string {.vshost.} =
    return "22"

let a = ("asd", "dsa")

for k,v in a.fieldPairs:
    echo k, ": ", v

var bb: Node
echo canHost(20, bb, nil)