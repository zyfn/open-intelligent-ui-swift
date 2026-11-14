import SwiftUI
@_exported import OpenUICore

// Source-compatible names for the generic renderer primitives.
// The implementation lives in OpenUICore; these aliases add no parallel runtime.
public typealias ComponentRegistry = OpenUICore.ComponentRegistry
public typealias RenderNode = OpenUICore.RenderNode
public typealias RenderValue = OpenUICore.RenderValue
public typealias PropValue = OpenUICore.PropValue
public typealias OpenUIRenderChild = OpenUICore.OpenUIRenderChild
public typealias ElementErrorBoundary<Content: SwiftUI.View> = OpenUICore.ElementErrorBoundary<Content>
