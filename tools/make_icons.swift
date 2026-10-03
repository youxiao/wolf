import AppKit
import Foundation
let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
func render(_ size: Int, _ path: String) {
 let s = CGFloat(size)
 let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size, bitsPerSample: 8, samplesPerPixel: 3, hasAlpha: false, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
 NSGraphicsContext.saveGraphicsState()
 NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
 NSColor(calibratedRed: 0.039, green: 0.063, blue: 0.086, alpha: 1).setFill()
 NSBezierPath(rect: NSRect(x:0,y:0,width:s,height:s)).fill()
 let gold = NSColor(calibratedRed: 0.8, green: 0.68, blue: 0.46, alpha: 1)
 gold.setStroke()
 for scale in [0.76, 0.65] {
  let path = NSBezierPath(ovalIn:NSRect(x:s*(1-scale)/2,y:s*(1-scale)/2,width:s*scale,height:s*scale))
  path.lineWidth = s * 0.006; path.stroke()
 }
 gold.setFill()
 NSBezierPath(ovalIn:NSRect(x:s*0.28,y:s*0.27,width:s*0.44,height:s*0.44)).fill()
 NSColor(calibratedRed: 0.039, green: 0.063, blue: 0.086, alpha: 1).setFill()
 NSBezierPath(ovalIn:NSRect(x:s*0.38,y:s*0.37,width:s*0.4,height:s*0.4)).fill()
 gold.setFill()
 for (x,y) in [(0.5,0.1),(0.5,0.9),(0.1,0.5),(0.9,0.5)] {
  NSBezierPath(ovalIn:NSRect(x:s*x-s*0.012,y:s*y-s*0.012,width:s*0.024,height:s*0.024)).fill()
 }
 NSGraphicsContext.restoreGraphicsState()
 let target=root.appendingPathComponent(path)
 try! FileManager.default.createDirectory(at:target.deletingLastPathComponent(),withIntermediateDirectories:true)
 try! rep.representation(using:.png,properties:[:])!.write(to:target)
}
for size in [16,32,64,128,256,512,1024] {render(size,"macos/Runner/Assets.xcassets/AppIcon.appiconset/app_icon_\(size).png")}
for (folder,size) in [("mdpi",48),("hdpi",72),("xhdpi",96),("xxhdpi",144),("xxxhdpi",192)] {render(size,"android/app/src/main/res/mipmap-\(folder)/ic_launcher.png")}
render(32,"web/favicon.png")
for size in [192,512] {render(size,"web/icons/Icon-\(size).png");render(size,"web/icons/Icon-maskable-\(size).png")}
let icons=root.appendingPathComponent("ios/Runner/Assets.xcassets/AppIcon.appiconset")
let json=try! JSONSerialization.jsonObject(with:Data(contentsOf:icons.appendingPathComponent("Contents.json"))) as! [String:Any]
for item in json["images"] as! [[String:Any]] {
 if let name=item["filename"] as? String, let sizeString=item["size"] as? String, let scaleString=item["scale"] as? String {
  let points=Double(sizeString.components(separatedBy:"x")[0])!
  let scale=Double(scaleString.replacingOccurrences(of:"x",with:""))!
  render(Int(points*scale),"ios/Runner/Assets.xcassets/AppIcon.appiconset/\(name)")
 }
}
print("Generated vector moon emblems for desktop, mobile and web.")
