import tables
import macros
import hashes

import variant
export variant

type VSDispatcher* = ref object
    blueprints*: Table[string, seq[proc(v: Variant)]]

proc createVSDispatcher*(): VSDispatcher=
    result.new()
    result.blueprints = initTable[string, seq[proc(v: Variant)]]()

proc dispatchAUX*(d: VSDispatcher, k: string, v: Variant) =
    var handlers = d.blueprints.getOrDefault(k)
    if not handlers.isNil:
        for h in handlers:
            h(v)

proc generateTuple(args: seq[NimNode]): NimNode =
    result = newNimNode(nnkPar)
    for i, arg in args:
        result.add(newNimNode(nnkExprColonExpr).add(ident("f" & $i)).add(arg))

macro dispatch*(b: varargs[untyped]): untyped =
    var args = newSeq[NimNode]()
    var packArgs = newSeq[NimNode]()

    var index = 0
    for bv in b.children:
        if index < 2:
            args.add(bv)
        else:
            packArgs.add(bv)
        inc index

    var packCall: NimNode
    if packArgs.len > 0:
        let t = generateTuple(packArgs)
        packCall = newCall(
            ident("newVariant"),
            t
        )
    else:
        packCall = newCall(ident("newVariant"))

    args.add(packCall)

    result = newCall(
        ident("dispatchAUX"),
        args
    )

    # echo "res ", repr(result)

template registerAUX(d: VSDispatcher, k: string, b: untyped)=
    var handlers = d.blueprints.getOrDefault(k)
    if handlers.isNil:
        handlers = @[]

    var handler = proc(v: Variant) =
        let args{.inject.} = v
        b

    handlers.add(handler)
    d.blueprints[k] = handlers

proc register*(d: VSDispatcher, k: string, cb: proc())=
    registerAUX(d, k):
        cb()

proc register*[T](d: VSDispatcher, k: string, cb: proc(v: T))=
    registerAUX(d, k):
        var val = args.get(T)
        cb(val)

proc register*[T, T2](d: VSDispatcher, k: string, cb: proc(v: T, v2: T2))=
    registerAUX(d, k):
        var val = args.get(tuple[f0:T, f1:T2])
        cb(val.f0, val.f1)
