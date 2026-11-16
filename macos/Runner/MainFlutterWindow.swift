import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    self.contentViewController = flutterViewController

    // Výchozí velikost okna 2000×1000 (zmenší se, pokud je obrazovka menší).
    // Velikost a polohu, kterou si uživatel nastaví, si macOS zapamatuje.
    self.minSize = NSSize(width: 900, height: 600)
    let restored = self.setFrameUsingName("FakturyHlavniOkno")
    if !restored, let screen = NSScreen.main ?? self.screen {
      let visible = screen.visibleFrame
      let width = min(2000, visible.width)
      let height = min(1000, visible.height)
      let frame = NSRect(
        x: visible.origin.x + (visible.width - width) / 2,
        y: visible.origin.y + (visible.height - height) / 2,
        width: width,
        height: height)
      self.setFrame(frame, display: true)
    }
    self.setFrameAutosaveName("FakturyHlavniOkno")

    RegisterGeneratedPlugins(registry: flutterViewController)

    super.awakeFromNib()
  }
}
