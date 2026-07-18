//
//  NativeEngineError.swift
//  hz
//
//  MIT License
//  See LICENSE file for details.

import Foundation

enum NativeEngineError: Error, Equatable {
    case unavailable
    case notImplemented(String)
    case invalidArgument(String)
    case allocationFailed(String)
    case internalError(String)
    case unknownStatus(Int32, String)
}
