import nimx / [ view, button, menu ]
import tables, strutils

type VSMenu* = ref object of View
    buttons: Table[string, Menu]

proc createVSMenu*(r: Rect): VSMenu =
    result.new()
    result.init(r)
    result.buttons = initTable[string, Menu]()
    result.backgroundColor = newColor(0.5, 0.5, 0.5, 0.5)

proc addMenuWithHandler*(v: VSMenu, path: string, cb: proc())=
    var spath = split(path, '/')
    var menu = v.buttons.getOrDefault(spath[0])
    
    let n = if spath.len > 0: spath[1 .. ^1].join(" ") else: path

    if menu.isNil:
        menu = newMenu()
        menu.children = @[]
        let x = v.buttons.len.float * 100.0
        var btn = newButton(newRect(x, 0, 100, v.frame.size.height))
        btn.title = spath[0]
        btn.onAction do():
            menu.popupAtPoint(v, btn.frame.origin + newPoint(0.0, btn.frame.size.height))
        v.addSubview(btn)

    var item = newMenuItem(n)
    item.action = proc() =
        cb()

    menu.children.add(item)
    v.buttons[spath[0]] = menu
    