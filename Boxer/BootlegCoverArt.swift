//
//  BootlegCoverArt.swift
//  Boxer
//
//  Created by C.W. Betts on 10/14/23.
//  Copyright © 2023 Alun Bestor and contributors. All rights reserved.
//

import Cocoa

extension BXBootlegCoverArt {
	func representation(for iconSize: NSSize) -> NSImageRep {
		return representation(for: iconSize, scale: 1)
	}
	
	static func coverArt(withTitle title: String) -> NSImage {
		return self.init(title: title).coverArt()
	}
}

class JewelCase : NSObject, BXBootlegCoverArt {
	required init(title coverTitle: String) {
		self.title = coverTitle
	}
	
	final var title: String
	
	final func draw(in frame: NSRect) {
		let iconSize = frame.size
		
		let baseLayer = type(of: self).baseLayer(for: iconSize)
		let topLayer = type(of: self).topLayer(for: iconSize)
		let textRegion = type(of: self).textRegion(for: frame)
		
		if let baseLayer {
			baseLayer.draw(in: frame, from: .zero, operation: .sourceOver, fraction: 1)
		}
		
		if !textRegion.isEmpty {
			let textAttributes = type(of: self).textAttributes(for: iconSize)
			title.draw(with: textRegion, attributes: textAttributes)
		}
		
		if let topLayer {
			topLayer.draw(in: frame, from: .zero, operation: .sourceOver, fraction: 1)
		}
	}
	
	final func representation(for iconSize: NSSize, scale: CGFloat) -> NSImageRep {
		let frame = NSRect(origin: .zero, size: iconSize)
		
		//Create a new empty canvas to draw into
		let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(iconSize.width*scale), pixelsHigh: Int(iconSize.height*scale), bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .calibratedRGB, bytesPerRow: 0, bitsPerPixel: 32)!
		rep.size = iconSize
		
		NSGraphicsContext.saveGraphicsState()
		NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
			draw(in: frame)
		NSGraphicsContext.restoreGraphicsState()
		
		return rep
	}
	
	final func coverArt() -> NSImage {
		let coverArt = NSImage()
		coverArt.addRepresentation(representation(for: NSSize(width: 512, height: 512), scale: 2))
		coverArt.addRepresentation(representation(for: NSSize(width: 512, height: 512), scale: 1))
		coverArt.addRepresentation(representation(for: NSSize(width: 256, height: 256), scale: 2))
		coverArt.addRepresentation(representation(for: NSSize(width: 256, height: 256), scale: 1))
		coverArt.addRepresentation(representation(for: NSSize(width: 128, height: 128), scale: 2))
		coverArt.addRepresentation(representation(for: NSSize(width: 128, height: 128), scale: 1))
		coverArt.addRepresentation(representation(for: NSSize(width: 32, height: 32), scale: 2))
		coverArt.addRepresentation(representation(for: NSSize(width: 32, height: 32), scale: 1))
		coverArt.addRepresentation(representation(for: NSSize(width: 16, height: 16), scale: 2))
		coverArt.addRepresentation(representation(for: NSSize(width: 16, height: 16), scale: 1))
		return coverArt
	}
	
	static func coverArt(withTitle title: String) -> NSImage {
		return self.init(title: title).coverArt()
	}
	
	/// Returns the font family name used for printing the title.
	open class var fontName: String {
		return "Marker Felt Thin"
	}
	
	/// Returns the color used for printing the title.
	open class var textColor: NSColor {
		return NSColor(red: 0, green: 0.1, blue: 0.2, alpha: 0.9)
	}

	/// Returns the line height used for printing the title.
	open class func lineHeight(for size: NSSize) -> CGFloat {
		return 20.0 * (size.width / 128.0)
	}

	/// Returns the font size used for printing the title.
	open class func fontSize(for size: NSSize) -> CGFloat {
		//Use smaller font at sizes > 128 so that we can fit more on the label
		let baseSize = (size.width > 128.0) ? 12.0 : 14.0
		return baseSize * (size.width / 128.0)
	}
	
	/// Returns a dictionary of `NSAttributedString` text attributes used for printing the title.
	/// This is a collection of the return values of the methods above.
	open class func textAttributes(for size: NSSize) -> [NSAttributedString.Key : Any] {
		let lineHeight	= lineHeight(for: size)
		let fontSize	= fontSize(for: size)
		let color		= self.textColor;
		let font		= NSFont(name: self.fontName, size: fontSize)
		
		let style = NSMutableParagraphStyle()
		style.alignment = .center
		style.maximumLineHeight = lineHeight
		style.minimumLineHeight = lineHeight
		
		return [.paragraphStyle: style,
				.font: font!,
				.foregroundColor: color,
				.ligature: 2]
	}

	/// Returns the image to render underneath the text.
	open class func baseLayer(for size: NSSize) -> NSImage? {
		return NSImage(named: "CDCase")
	}
	
	/// Returns the image to render over the top of the text.
	open class func topLayer(for size: NSSize) -> NSImage? {
		//At sizes below 128x128 we don't use the cover-glass image
		if size.width >= 128 {
			return NSImage(named: "CDCover")
		}
		return nil
	}

	/// Returns the region of the image in which to print the text.
	/// Will be `NSRect.zero` if text should not be printed at this size.
	open class func textRegion(for rect: NSRect) -> NSRect {
		if rect.size.width >= 128 {
			let scale = rect.size.width / 128.0
			return NSRect(x: 22.0 * scale,
						  y: 32.0 * scale,
						  width: 92.0 * scale,
						  height: 60.0 * scale)
		}
		//Do not show text on icon sizes below 128x128.
		return .zero
	}
}

final class Diskette35: JewelCase {
	override class func baseLayer(for size: NSSize) -> NSImage? {
		return NSImage(named: "35Diskette")
	}
	
	override class func topLayer(for size: NSSize) -> NSImage? {
		if size.width >= 128 {
			return NSImage(named: "35DisketteShine")
		}
		return nil
	}
	
	override class func lineHeight(for size: NSSize) -> CGFloat {
		return 18.0 * (size.width / 128.0)
	}
	
	override class func textRegion(for rect: NSRect) -> NSRect {
		if rect.size.width >= 128 {
			let scale = rect.size.width / 128.0
			return NSRect(x: 24.0 * scale,
						  y: 56.0 * scale,
						  width: 80.0 * scale,
						  height: 56.0 * scale)
		}
		return .zero
	}
}

final class Diskette525: JewelCase {
	override class func baseLayer(for size: NSSize) -> NSImage? {
		return NSImage(named: "525Diskette")
	}
	
	override class func topLayer(for size: NSSize) -> NSImage? {
		return nil
	}
	
	override class func lineHeight(for size: NSSize) -> CGFloat {
		16.0 * (size.width / 128.0)
	}
	
	override class func fontSize(for size: NSSize) -> CGFloat {
		12.0 * (size.width / 128.0)
	}
	
	override class func textRegion(for rect: NSRect) -> NSRect {
		if rect.size.width >= 128 {
			let scale = rect.size.width / 128.0
			return NSRect(x: 16.0 * scale,
						  y: 90.0 * scale,
						  width: 96.0 * scale,
						  height: 32.0 * scale)
		}

		return .zero
	}
}
