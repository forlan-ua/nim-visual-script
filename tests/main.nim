import nimx / [ view, window ]
import visual_script / editor / vse_editor

proc startApplication() =
    let mainWindow = newWindow(newRect(40, 40, 1280, 720))

    mainWindow.title = "VSE: Visual Script Editor"

    var editor = new(VSNetworkView)
    editor.init(mainWindow.bounds)
    editor.autoResizingMask = {afFlexibleWidth, afFlexibleHeight}
    mainWindow.addSubview(editor)

runApplication:
    startApplication()