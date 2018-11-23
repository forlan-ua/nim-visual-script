import nimx / [types, view, panel_view, text_field, button]
import vse_types

proc popupRect(v: View): Rect =
    let size = newSize(200.0, 100.0)
    result.origin.x = v.bounds.width * 0.5 - size.width * 0.5
    result.origin.y = v.bounds.height * 0.5 - size.height * 0.5
    result.size.width = size.width
    result.size.height = size.height

proc tfRect(v: View): Rect=
    result.origin.x = 5
    result.origin.y = 5
    result.size.width = v.bounds.size.width - 10.0
    result.size.height = 20

proc newTfPopup*(v: View, continuous: bool,  cb: proc(str: string)) =
    let r = new(VSETfPopup)
    r.init(v.popupRect)

    r.backgroundColor = newColor(0.0, 0.0, 0.0, 0.8)

    var tf = newTextField(r.tfRect)
    tf.continuous = continuous
    tf.onAction do():
        cb(tf.text)
    r.addSubview(tf)

    var btn = newButton(newRect(r.bounds.width * 0.5 - 20.0, r.bounds.height - 20, 40, 15))
    btn.title = "ok"
    btn.onAction do():
        r.removeFromSuperview()
    r.addSubview(btn)

    v.addSubview(r)
