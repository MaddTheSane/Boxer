//
//  MT32LCDDisplay.swift
//  Boxer
//
//  Created by C.W. Betts on 10/7/23.
//  Copyright © 2023 Alun Bestor and contributors. All rights reserved.
//

import Cocoa

/// BXMT32LCDDisplay imitates, as the name suggests, the LCD display on a Roland MT-32 Sound Module.
/// It is used for displaying messages sent by the games to the emulated MT-32. (Many Sierra games
/// would send cheeky messages to it on startup.)
///
/// This field can only display ASCII characters, as that was all the MT-32's display could handle.
/// Non-ASCII characters will be drawn as empty space.
class MT32LCDDisplay : NSTextField {
    /// The image containing glyph data for the pixel font.
    private var pixelFont: NSImage {
        return NSImage(named: "MT32ScreenDisplay/MT32LCDFontTemplate")!
    }
    
    /// The mask image to use for the LCD pixel grid.
    /// This will be drawn in for 20 character places.
    private var pixelGrid: NSImage {
        return NSImage(named: "MT32ScreenDisplay/MT32LCDGridTemplate")!
    }
    
    /// The background color of the field.
    private var screenColor: NSColor {
        return NSColor(named: "MT32ScreenDisplay/screenColor")!
    }

    private var frameColor: NSColor {
        return NSColor(named: "MT32ScreenDisplay/frameColor")!
    }

    /// The background color of the LCD pixel grid.
    private var gridColor: NSColor {
        return NSColor(named: "MT32ScreenDisplay/gridColor")!
    }

    /// The colour of lit LCD pixels upon the grid.
    private var pixelColor: NSColor {
        return NSColor(named: "MT32ScreenDisplay/pixelColor")!
    }
    
    /// The inner shadow of the screen.
    private var innerShadow: NSShadow {
        return NSShadow(blurRadius: 10, offset: NSSize(width: 0, height: -2.0), color: NSColor(named: "MT32ScreenDisplay/innerShadowColor")!)
    }
    
    /// The lighting effects applied on top of the screen.
    private var screenLighting: NSGradient {
        return NSGradient(colorsAndLocations: (NSColor(calibratedWhite: 1.0, alpha: 0.10), 0.0), (NSColor(calibratedWhite: 1.0, alpha: 0.07), 0.5), (NSColor.clear, 0.55))!
    }
    
    override func draw(_ dirtyRect: NSRect) {
        let charsToDisplay = stringValue.padding(toLength: 20, withPad: " ", startingAt: 0)
        
        let fontTemplate = pixelFont
        let gridTemplate = pixelGrid
        
        let screenShadow = innerShadow
        let screenColor = self.screenColor
        
        let screenPath = NSBezierPath(roundedRect: bounds, xRadius: 4, yRadius: 4)
        
        //First, draw the screen itself
        NSGraphicsContext.saveGraphicsState()
            screenColor.set()
            screenPath.fill()
        NSGraphicsContext.restoreGraphicsState()

        let gridColor = self.gridColor
        let glyphColor = self.pixelColor
        
        let characterSize = gridTemplate.size
        let characterSpacing: CGFloat = 3
        
        let glyphSize = NSSize(width: 5, height: 9)
        let firstGlyph: Character = "!"
        
        var gridRect = NSRect(origin: .zero, size: CGSize(width: (characterSize.width + characterSpacing) * 19 + characterSize.width, height: characterSize.height))
        
        gridRect = centerInRect(gridRect, bounds)
        gridRect.origin = integralPoint(gridRect.origin)
        
        let fontTemplateRect = NSRect(origin: .zero, size: fontTemplate.size)
        let gridTemplateRect = NSRect(origin: .zero, size: gridTemplate.size)
        
        var characterRect = NSRect(origin: gridRect.origin, size: characterSize)
        
        let grid = gridTemplate.imageFilled(with: gridColor, at: characterSize)
        
        for (i, c) in charsToDisplay.enumerated() {
            if i >= 20 {
                break
            }
            
            //First, draw the background grid for this character
            grid.draw(in: characterRect, from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
            
            //Next, draw the glyph to show in this grid, if it's within
            //the range of our drawable characters
            let glyphOffset = Int(c.asciiValue ?? 0) - Int(firstGlyph.asciiValue!)
            
            //The place in the font image to grab the glyph from
            let glyphRect = NSRect(x: CGFloat(glyphOffset) * glyphSize.width, y: 0,
                                   width: glyphSize.width, height: glyphSize.height)

            //Only bother drawing the character if it's represented in our glyph image.
            if NSContainsRect(fontTemplateRect, glyphRect) {
                let maskedGlyph = gridTemplate.copy() as! NSImage
                
                //First, use the grid to mask the glyph
                maskedGlyph.lockFocus()
                //Disable interpolation to ensure crisp scaling when we redraw the glyph.
                NSGraphicsContext.current?.imageInterpolation = .none
                fontTemplate.draw(in: gridTemplateRect, from: glyphRect, operation: .destinationIn, fraction: 1, respectFlipped: true, hints: nil)
                maskedGlyph.unlockFocus()
                
                //Then, draw the masked glyph into the itself
                let tintedGlyph = maskedGlyph.imageFilled(with: glyphColor, at: .zero)
                
                tintedGlyph.draw(in: characterRect, from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
            }
            
            characterRect.origin.x += characterSize.width + characterSpacing
        }
        
        //Finally, draw the shadowing and lighting effects and the frame
        NSGraphicsContext.current?.saveGraphicsState()
        screenPath.fill(withInnerShadow: screenShadow)
        frameColor.setStroke()
        screenPath.lineWidth = 2
        screenPath.strokeInside()
        screenLighting.draw(in: screenPath, angle: 80)
        NSGraphicsContext.current?.restoreGraphicsState()
    }
}
