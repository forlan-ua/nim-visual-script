import tables
import nimx / [
    types, view, button, text_field, panel_view, context, event,
    view_dragging_listener, font, formatted_text, gesture_detector
]
import sequtils

var defaultFont*: Font = systemFontOfSize(16.0)

var colorTable* = initTable[string, Color]()

const portStep* = 35.0

const pinSize* = newSize(25.0, 25.0)
const pinDefaultColor* = whiteColor()
const pinConnectedColor* = newColor(0.1, 0.8, 0.2, 1.0)
const pinDragColor* = newColor(0.2, 0.1, 0.8, 1.0)
const pinConnectErrorColor* = newColor(0.8, 0.2, 0.0, 1.0)
const pinConnectOKColor* = pinConnectedColor
const flowColor* = newColor(0, 0.75, 1.0, 1.0)
const lineDragColor* = blackColor()
const lineConnectedColor* = pinConnectedColor
const VSFLOWTYPE* = "VSFlow"

type PortInfo* = tuple
    name: string
    typ: string
    value: string
    active: bool

type HostInfo* = tuple
    name: string
    inputPorts: seq[PortInfo]
    outputPorts: seq[PortInfo]
    isDispatcher: bool

type
    PortViewScrollListner* = ref object of OnScrollListener
        port*: VSPortView

    VSPortView* = ref object of View
        isFlow*: bool
        connections*: seq[VSPortView]
        orientation*: bool
        pinColor*: Color
        info*: PortInfo
        listner*: VSPortListner
        pinPosition*: Point
        host*: VSHostView
        defaultValue*: string

    VSHostView* = ref object of PanelView
        input*: seq[VSPortView]
        output*: seq[VSPortView]
        info*: HostInfo
        network*: VSNetworkView
        id*: int

    VSPortListner* = ref object
        onPortDrag*: proc(p: Point)
        onPortDragEnd*: proc(p: VSPortView)
        onPortDragStart*: proc(p: VSPortView)

        onPortOverIn*: proc(p: VSPortView)
        onPortOverOut*: proc(p: VSPortView)

    VSNetworkView* = ref object of View
        hosts*: seq[VSHostView]
        connections*: seq[tuple[a: VSPortView, b: VSPortView]]
        networkContent*: View
        portsListner*: VSPortListner
        dragStartPort*: VSPortView
        overPort*: VSPortView
        dragStartPoint*: Point
        dragPosition*: Point
        currHostID*: int

    VSEditorView* = ref object of View
        networks*: Table[string, VSNetworkView]
        currentNetwork*: VSNetworkView
        networksSuperView*: View

    VSETfPopup* = ref object of PanelView
        onText*: proc(str: string)
    VSEFindPopup* = ref object of VSETfPopup

    VSEHostCreator* = proc(info: HostInfo): VSHostView

proc canHandleDefaultValue*(v: VSPortView): bool =
    v.info.typ in ["bool", "int", "int8", "int16", "int32", "string", "char", "float"]

# literal have flow input port
proc isLitHost*(i: HostInfo): bool = i.inputPorts.len == 1

#flow hosts should have more that 1 input or/and 1 output FLOW ports
proc isFlowHost*(i: HostInfo): bool =
    let comp = proc(p: PortInfo): bool = p.typ == "VSFlow"
    result = i.inputPorts.filter(comp).len > 1
    if not result:
        result = i.outputPorts.filter(comp).len > 1
