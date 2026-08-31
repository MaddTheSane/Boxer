//
//  File.swift
//  Boxer
//
//  Created by C.W. Betts on 10/22/19.
//  Copyright © 2019 Alun Bestor and contributors. All rights reserved.
//

import Foundation
import CwlDemangle
import RegexBuilder

private enum MangledFunctionType {
    /// No detected mangling
    case none
    /// *C++* mangled function name
    case cPlusPlus
    /// *Swift* mangled name
    case swift
}

private let swiftPrefixes = ["_T", "$s", "_$S", "_T0"]
private let cxxPrefixes = ["_Z"]

private let ADBCallstackSymbolPattern = #"^\d+\s+(\S+)\s+(0x[a-fA-F0-9]+)\s+(.+)\s+\+\s+(\d+)$"#
@available(macOS 13.0, *)
private let ADBCallstackSymbolPatternNew = Regex {
	Anchor.startOfLine
    OneOrMore(.digit)
    OneOrMore(.whitespace)
    Capture {
        OneOrMore(.whitespace.inverted)
    }
    OneOrMore(.whitespace)
    "0x"
    Capture {
		OneOrMore(.hexDigit)
	} transform: { UInt64($0, radix: 16)! }
    OneOrMore(.whitespace)
    Capture {
		OneOrMore (.anyNonNewline)
    }
    OneOrMore(.whitespace)
    "+"
    OneOrMore(.whitespace)
    Capture {
        OneOrMore(.digit)
	} transform: { Int64($0)! }
	Anchor.endOfLine
}

extension NSException {
    private static func possibleMangledType<A>(from: A) -> MangledFunctionType where A : StringProtocol {
        //Short-circuit if there's less than two characters.
        guard from.count > 2 else {
            return .none
        }
        var trimFirst = false
        if from.first == "_" {
            trimFirst = true
        }
        for pref in swiftPrefixes {
            if from.starts(with: pref) {
                return .swift
            }
        }
        for pref in cxxPrefixes {
            if from.starts(with: pref) {
                return .cPlusPlus
            }
        }
        if trimFirst {
            let tmpInd = from.index(from.startIndex, offsetBy: 1)
            let tmpFrom = from[tmpInd..<from.endIndex]
//            tmpFrom.removeFirst()
            return possibleMangledType(from: tmpFrom)
        }
        
        return .none
    }
    
	/// Takes a mangled Swift function name produced by `callstackSymbols` or `backtrace_symbols` and returns a demangled version.
	/// Returns `nil` if the provided string could not be resolved (which will be the case if it is a C, Objective C, or C++ symbol name).
    private static func demangledSwiftFunctionName<A>(_ functionName: A) -> String? where A : StringProtocol {
        guard let parsed = try? parseMangledSwiftSymbol(functionName.unicodeScalars, isType: true) else {
            return nil
        }
        return parsed.description
    }
    
    /// Returns the results of `-callstackSymbols` parsed into NSDictionaries with the attributes listed in ``ADBCallstackKeys``.
    @objc func callStackDescriptions() -> [[ADBCallstackKeys: Any]] {
        let symbols = callStackSymbols
        
        return symbols.map { symbol -> [ADBCallstackKeys: Any] in
            if #available(macOS 13.0, *) {
                guard let captures = (try? ADBCallstackSymbolPatternNew.wholeMatch(in: symbol))?.output else {
                    //If the string couldn't be parsed, make an effort to provide *something* back
                    return [.rawSymbol: symbol]
                }
                let libraryName = String(captures.1)
				let address = captures.2
                let rawSymbolName = captures.3
				let rawSymbolNameStr = String(rawSymbolName)
				let offset = captures.4
				
                let symbolType = NSException.possibleMangledType(from: rawSymbolName)
                var demangledSymbolName: String?
                switch symbolType {
                case .none:
                    demangledSymbolName = rawSymbolNameStr
                    
                case .cPlusPlus:
                    demangledSymbolName = NSException.demangledCPlusPlusFunctionName(rawSymbolNameStr)
                    
                case .swift:
                    demangledSymbolName = NSException.demangledSwiftFunctionName(rawSymbolName)
                }
                if demangledSymbolName == nil {
                    demangledSymbolName = rawSymbolNameStr
                }
                
                return [
                    .rawSymbol:                    symbol,
                    .libraryName:                  libraryName,
                    .functionName:                 rawSymbolNameStr,
                    .humanReadableFunctionName:    demangledSymbolName!,
                    .address:                      address,
                    .symbolOffset:                 offset]
            }
            if let captures = (symbol as NSString).captureComponentsMatched(byRegex: ADBCallstackSymbolPattern), captures.count == 5 {
                // FIXME: reimplement this using NSScanner or NSRegularExpression so that we don't have dependencies on RegexKitLite.
                let libraryName = captures[1]
                let hexAddress = captures[2]
                let rawSymbolName = captures[3]
                let offsetString = captures[4]
                
                var address: UInt64 = 0
                let hexAddressScanner = Scanner(string: hexAddress)
                hexAddressScanner.scanHexInt64(&address)
                
                var offset: Int64 = 0
                let offsetScanner = Scanner(string: offsetString)
                offsetScanner.scanInt64(&offset)
                
                let symbolType = NSException.possibleMangledType(from: rawSymbolName)
                var demangledSymbolName: String?
                switch symbolType {
                case .none:
                    demangledSymbolName = rawSymbolName
                    
                case .cPlusPlus:
                    demangledSymbolName = NSException.demangledCPlusPlusFunctionName(rawSymbolName)
                    
                case .swift:
                    demangledSymbolName = NSException.demangledSwiftFunctionName(rawSymbolName)
                }
                if demangledSymbolName == nil {
                    demangledSymbolName = rawSymbolName
                }
                return [
                    .rawSymbol:                    symbol,
                    .libraryName:                  libraryName,
                    .functionName:                 rawSymbolName,
                    .humanReadableFunctionName:    demangledSymbolName!,
                    .address:                      address,
                    .symbolOffset:                 offset]
            } else {
                //If the string couldn't be parsed, make an effort to provide *something* back
                return [.rawSymbol: symbol]
            }
        }
    }
}
