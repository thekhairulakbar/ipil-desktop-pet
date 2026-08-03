// Ipil pixel sprite frames — drawn in the established Ipil favicon style.
// Canon: warm-orange munchkin cat, narrow slanted eyes, smaller/closed left ear,
// subtle brown nose mottling, full tail, stubby legs. All frames face LEFT.

import AppKit

enum SpriteFrame: CaseIterable {
    case walk1, walk2, stand, sleep, sit, groom, tailflick, stretch
}

enum Sprite {
    static let gridWidth = 24
    static let gridHeight = 16

    static let palette: [Character: NSColor] = [
        "O": NSColor(red: 214/255, green: 124/255, blue: 40/255, alpha: 1),
        "D": NSColor(red: 176/255, green: 94/255, blue: 28/255, alpha: 1),
        "K": NSColor(red: 22/255, green: 20/255, blue: 18/255, alpha: 1),
        "W": NSColor(red: 246/255, green: 238/255, blue: 224/255, alpha: 1),
        "P": NSColor(red: 146/255, green: 88/255, blue: 66/255, alpha: 1),
        "Z": NSColor(red: 120/255, green: 62/255, blue: 20/255, alpha: 1),
    ]

    static let walk1 = [
        "........................",
        "..DD....D...............",
        "..DOD..DD...............",
        "..DOOD.DOD..........DD..",
        ".DOOOOOOOO.........DOD..",
        ".DOKKOOOOO........DOD...",
        ".DOOOOOOOO.......DOD....",
        ".WPWOOOOOOO.....DOO.....",
        ".WWWOOOOOOOOOOOOOO......",
        "..WWOOOOOOOOOOOOOO......",
        "..OOOOOOOOOOOOOOOO......",
        "...OOOOOOOOOOOOOO.......",
        "...OOO..OOO...OOO.......",
        "...DOO..OOD...OOD.......",
        "........................",
        "........................",
    ]

    static let walk2 = [
        "........................",
        "..DD....D...............",
        "..DOD..DD...............",
        "..DOOD.DOD..........DD..",
        ".DOOOOOOOO..........DOD.",
        ".DOKKOOOOO.........DOD..",
        ".DOOOOOOOO........DOD...",
        ".WPWOOOOOOO......DOO....",
        ".WWWOOOOOOOOOOOOOO......",
        "..WWOOOOOOOOOOOOOO......",
        "..OOOOOOOOOOOOOOOO......",
        "...OOOOOOOOOOOOOO.......",
        "....OOO...OOO..OOO......",
        "....OOD...DOO..DOO......",
        "........................",
        "........................",
    ]

    static let stand = [
        "........................",
        "..DD....D...............",
        "..DOD..DD...............",
        "..DOOD.DOD..........DD..",
        ".DOOOOOOOO.........DOD..",
        ".DOKKOOOOO........DOD...",
        ".DOOOOOOOO.......DOD....",
        ".WPWOOOOOOO.....DOO.....",
        ".WWWOOOOOOOOOOOOOO......",
        "..WWOOOOOOOOOOOOOO......",
        "..OOOOOOOOOOOOOOOO......",
        "...OOOOOOOOOOOOOO.......",
        "...OOO.OOO.OOO.OO.......",
        "...OOD.OOD.OOD.OD.......",
        "........................",
        "........................",
    ]

    static let sleep = [
        "........................",
        "........................",
        "........................",
        "........................",
        "....DD....D.............",
        "....DOD..DD.............",
        "....DOODDOOD............",
        "...DOOOOOOOOOOOOOOD.....",
        "...DOZZOOOOOOOOOOOOD....",
        "...DOOOOOOOOOOOOOOOOD...",
        "..DOOOOOOOOOOOOOOOOOD...",
        "..DOOOOOOOOOOOOOOOOD....",
        "..DOODDDOOOOOOOOOOD.....",
        "...DDD..DDDDDDDDDD......",
        "........................",
        "........................",
    ]

    static let sit = [
        "........................",
        "....DD....D.............",
        "....DOD..DD.............",
        "....DOOD.DOD............",
        "...DOOOOOOOO............",
        "...DOKKOOOOO............",
        "...DOOOOOOOO............",
        "...WPWOOOOOO............",
        "...WWWOOOOOOO...........",
        "....WWOOOOOOOO....DD....",
        "....OOOOOOOOOOO..DOD....",
        "....OOOOOOOOOOO.DOD.....",
        "....OOOOOOOOOOOODO......",
        "....OOO.OOOOOOOOO.......",
        "....OOD..OODDOOD........",
        "........................",
    ]

    // Grooming: sitting, head bent down, eyes closed, cream paw raised to the chest
    static let groom = [
        "........................",
        "........................",
        "........................",
        "....DD....D.............",
        "....DOD..DD.............",
        "....DOODDOOD............",
        "...DOOOOOOOO............",
        "...DOZZOOOOO............",
        "...WPWOOOOOO............",
        "...WWWOOOOOOO.....DD....",
        "....WWOOWWOOOO...DOD....",
        "....OOOWWOOOOOO.DOD.....",
        "....OOOOOOOOOOOODO......",
        "....OOO.OOOOOOOOO.......",
        "....OOD..OODDOOD........",
        "........................",
    ]

    // Tail flick: standing, tail curled forward over the back
    static let tailflick = [
        "........................",
        "..DD....D......DDD......",
        "..DOD..DD......DODD.....",
        "..DOOD.DOD......DOD.....",
        ".DOOOOOOOO.......DOD....",
        ".DOKKOOOOO........DO....",
        ".DOOOOOOOO........DO....",
        ".WPWOOOOOOO......DOO....",
        ".WWWOOOOOOOOOOOOOO......",
        "..WWOOOOOOOOOOOOOO......",
        "..OOOOOOOOOOOOOOOO......",
        "...OOOOOOOOOOOOOO.......",
        "...OOO.OOO.OOO.OO.......",
        "...OOD.OOD.OOD.OD.......",
        "........................",
        "........................",
    ]

    // Stretch: the classic play-bow — chest low, front legs out, rear and tail up
    static let stretch = [
        "........................",
        "........................",
        "........................",
        "....................DD..",
        "...................DOD..",
        "..................DOD...",
        "..DD....D........DOO....",
        "..DOD..DD......OOOOO....",
        "..DOOD.DOD...OOOOOOO....",
        ".DOOOOOOOOOOOOOOOOOO....",
        ".DOKKOOOOOOOOOOOOOO.....",
        ".DOOOOOOOOOOOOOOO.......",
        ".WPWOOOOO...OOOO........",
        ".WWWOO.OO...OOD.........",
        "..DDD..DD...............",
        "........................",
    ]

    static func grid(for frame: SpriteFrame) -> [String] {
        switch frame {
        case .walk1: return walk1
        case .walk2: return walk2
        case .stand: return stand
        case .sleep: return sleep
        case .sit: return sit
        case .groom: return groom
        case .tailflick: return tailflick
        case .stretch: return stretch
        }
    }

    // Draw a frame into the given rect. Grids face left; pass flipped=true to face right.
    static func draw(_ frame: SpriteFrame, in rect: NSRect, flipped: Bool) {
        let grid = self.grid(for: frame)
        let px = rect.width / CGFloat(gridWidth)
        let py = rect.height / CGFloat(gridHeight)
        for (rowIndex, row) in grid.enumerated() {
            for (colIndex, ch) in row.enumerated() {
                guard ch != ".", let color = palette[ch] else { continue }
                let x = flipped ? CGFloat(gridWidth - 1 - colIndex) : CGFloat(colIndex)
                // Grid rows are top-to-bottom; view coords are bottom-up.
                let y = CGFloat(gridHeight - 1 - rowIndex)
                let cell = NSRect(
                    x: rect.minX + x * px,
                    y: rect.minY + y * py,
                    width: px + 0.5,
                    height: py + 0.5
                )
                color.setFill()
                cell.fill()
            }
        }
    }
}
