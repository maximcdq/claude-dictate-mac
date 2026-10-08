import CoreGraphics
import Foundation

// The mic level an indicator shows. The app's meter records it; the indicators only start, read and stop it.
public protocol LevelSource: AnyObject {
    var level: CGFloat { get }  // 0...1, Claude Code's scale: sqrt(min(rms16 / 2000, 1))
    var heardAt: Date? { get }  // the first audio since start
    func start()
    func stop()
    func watch()  // every frame while recording: lets the source notice it went quiet and recover
}
