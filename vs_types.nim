
type VSPortKind* = enum
    Input
    Output


type VSPort*[T]= ref object of RootObj
    name*: string
    kind*: VSPortKind
    connections*: seq[VSPort[T]]
    onUpdate*: proc()
    data*: T

proc connect*(p1: VSPort, p2: varargs[VSPort]) =
    for c in p2:
        if p1.connections.find(c) == -1:
            p1.connections.add(c)

        if c.connections.find(p1) == -1:
            c.connections.add(p1)

        p1.data = c.data

proc disconnect*(p1: VSPort, p2: varargs[VSPort]) =
    for c in p2:
        let ind1 = p1.connections.find(c)
        if ind1 > -1:
            p1.connections.del(ind1)

        let ind2 = c.connections.find(p1)
        if ind2 > -1:
            c.connections.del(ind2)

proc deepUpdate*(p: VSPort) =
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

proc newVSPort*(T: typedesc, kind: VSPortKind): VSPort[T] =
    result.new()
    result.kind = kind
    result.connections = @[]

type VSHost* = ref object of RootObj
    name*: string

method invoke*(h: VSHost) {.base.} = discard

proc listen*(h: VSHost, p: VSPort) =
    p.onUpdate =  proc() =
        h.invoke()
