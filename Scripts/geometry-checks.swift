import Foundation
import CoreGraphics
import CoreImage

@main struct GeometryChecks {
 static func pixels(_ image: CGImage) -> [UInt8] {
  let context = CGContext(data:nil,width:image.width,height:image.height,bitsPerComponent:8,bytesPerRow:image.width*4,space:CGColorSpace(name:CGColorSpace.sRGB)!,bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue)!
  context.draw(image,in:CGRect(x:0,y:0,width:image.width,height:image.height))
  return Array(UnsafeBufferPointer(start:context.data!.assumingMemoryBound(to:UInt8.self),count:image.width*image.height*4))
 }
 static func main() {
  let w=200,h=120
  var data=[UInt8]()
  for y in 0..<h { for x in 0..<w {
   data += [UInt8(x),UInt8(y),UInt8((x+y)%255),255]
  }}
  let cg=CGImage(width:w,height:h,bitsPerComponent:8,bitsPerPixel:32,bytesPerRow:w*4,space:CGColorSpace(name:CGColorSpace.sRGB)!,bitmapInfo:CGBitmapInfo(rawValue:CGImageAlphaInfo.premultipliedLast.rawValue),provider:CGDataProvider(data:Data(data) as CFData)!,decode:nil,shouldInterpolate:false,intent:.defaultIntent)!
  let baseline=pixels(cg)
  var count=0
  for q in 0..<4 { for fh in [false,true] { for fv in [false,true] {
   let g=ImageGeometry(quarterTurns:q,flippedHorizontally:fh,flippedVertically:fv)
   let out=GeometryRenderer.render(cg,geometry:g)!
   precondition(out.width==(q%2==0 ? w:h) && out.height==(q%2==0 ? h:w))
   var rotated=g;rotated.rotateLeft()
   let direct=GeometryRenderer.render(cg,geometry:rotated)!
   let repeated=GeometryRenderer.render(out,geometry:ImageGeometry(quarterTurns:1))!
   precondition(pixels(direct)==pixels(repeated),"Quarter turn composition")
   var horizontal=g;horizontal.flipHorizontal()
   let hdirect=GeometryRenderer.render(cg,geometry:horizontal)!
   let hrepeated=GeometryRenderer.render(out,geometry:ImageGeometry(flippedHorizontally:true))!
   precondition(pixels(hdirect)==pixels(hrepeated),"Horizontal flip composition")
   count += 1
  }}}
  var selection=CropSelection(normalizedRect:CGRect(x:0.1,y:0.2,width:0.4,height:0.5))
  let before=cg.cropping(to:selection.pixelRect(in:CGSize(width:w,height:h)))!
  selection.rotateLeft(imageAspect:CGFloat(w)/CGFloat(h))
  let whole=GeometryRenderer.render(cg,geometry:ImageGeometry(quarterTurns:1))!
  let after=whole.cropping(to:selection.pixelRect(in:CGSize(width:h,height:w)))!
  let expected=GeometryRenderer.render(before,geometry:ImageGeometry(quarterTurns:1))!
  precondition(pixels(after)==pixels(expected),"Crop region rotates with source")
  for angle in [-45.0,-30,-1,0.1,1,30,45] {
   let g=ImageGeometry(straightenDegrees:angle)
   let out=GeometryRenderer.render(cg,geometry:g)!
   let p=pixels(out)
   precondition(stride(from:3,to:p.count,by:4).allSatisfy{p[$0]==255},"Transparent rotation corner at \(angle)")
   precondition(out.width == w && out.height == h)
   let zoom=g.constrainedScale(in:CGSize(width:w,height:h))
   let radians=angle * .pi / 180
   for x in [-Double(w)/2, Double(w)/2] { for y in [-Double(h)/2, Double(h)/2] {
    let ix=(cos(radians)*x+sin(radians)*y)/zoom
    let iy=(-sin(radians)*x+cos(radians)*y)/zoom
    precondition(abs(ix)<Double(w)/2 && abs(iy)<Double(h)/2)
   }}
   count += 1
  }
  precondition(pixels(cg)==baseline)
  precondition(CropSelection().aspect == .original)
  print("PASS: \(count) image geometry configurations; exact dimensions, transform composition, ROI rotation, opaque constrained corners and source preservation")
 }
}
