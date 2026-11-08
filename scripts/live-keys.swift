// Live-test input for agents (docs/live-test.md): real key presses at the HID level, through every event tap and the input
// method, to the frontmost app. Run: swift scripts/live-keys.swift "t:Please let me know if you have any" w:3000 k:tab
// Args: "t:text" (ABC keys; with the Korean 2-set source on, the same keys compose Hangul: "t:dhsmf" types 오늘),
// "k:tab" "k:shift+tab" "k:esc" "k:ret" "k:bs" "k:left" "k:right" "k:shiftup", "c:a" (Cmd-A), "m:x,y" (click, in points),
// "w:ms", "fast" / "slow". Never "k:ret" in a chat app: it sends.
import CoreGraphics
import Foundation
let map: [Character: CGKeyCode] = ["a":0,"s":1,"d":2,"f":3,"h":4,"g":5,"z":6,"x":7,"c":8,"v":9,"b":11,"q":12,"w":13,"e":14,"r":15,"y":16,"t":17,"1":18,"2":19,"3":20,"4":21,"6":22,"5":23,"=":24,"9":25,"7":26,"-":27,"8":28,"0":29,"]":30,"o":31,"u":32,"[":33,"i":34,"p":35,"l":37,"j":38,"'":39,"k":40,";":41,"\\":42,",":43,"/":44,"n":45,"m":46,".":47," ":49]
let named: [String: CGKeyCode] = ["shiftup":56,"tab":48,"esc":53,"ret":36,"bs":51,"left":123,"right":124]
var gap: useconds_t = 90_000
func press(_ code: CGKeyCode, shift: Bool = false, cmd: Bool = false) {
    let src = CGEventSource(stateID: .hidSystemState)
    for down in [true, false] {
        let e = CGEvent(keyboardEventSource: src, virtualKey: code, keyDown: down)!
        e.flags = shift ? .maskShift : cmd ? .maskCommand : []
        e.post(tap: .cghidEventTap)
        usleep(8_000)
    }
    usleep(gap)
}
for arg in CommandLine.arguments.dropFirst() {
    if arg == "fast" { gap = 15_000; continue }
    if arg == "slow" { gap = 90_000; continue }
    let (kind, rest) = (arg.prefix(2), String(arg.dropFirst(2)))
    switch kind {
    case "t:": for ch in rest { let low = Character(ch.lowercased()); press(map[low]!, shift: ch.isUppercase) }
    case "c:": press(map[Character(rest)]!, cmd: true)
    case "k:": let shift = rest.hasPrefix("shift+"); press(named[shift ? String(rest.dropFirst(6)) : rest]!, shift: shift)
    case "m:":
        let xy = rest.split(separator: ",").map { Double($0)! }
        for type in [CGEventType.leftMouseDown, .leftMouseUp] {
            CGEvent(mouseEventSource: nil, mouseType: type, mouseCursorPosition: CGPoint(x: xy[0], y: xy[1]), mouseButton: .left)!.post(tap: .cghidEventTap)
            usleep(30_000)
        }
    case "w:": usleep(useconds_t(Int(rest)! * 1000))
    default: fatalError(arg)
    }
}
