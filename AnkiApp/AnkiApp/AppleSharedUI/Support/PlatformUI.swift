import SwiftUI

#if os(macOS)
import AppKit
public typealias PlatformImage = NSImage
#elseif os(iOS)
import UIKit
public typealias PlatformImage = UIImage
#endif

public struct PlatformImageView: View {
    public let image: PlatformImage

    public init(image: PlatformImage) {
        self.image = image
    }

    public var body: some View {
        #if os(macOS)
        Image(nsImage: image)
            .resizable()
        #else
        Image(uiImage: image)
            .resizable()
        #endif
    }
}

public struct AppIconView: View {
    public init() {}

    public var body: some View {
        #if os(macOS)
        Image(nsImage: NSApp.applicationIconImage)
            .resizable()
        #else
        Image(systemName: "rectangle.stack.fill")
            .resizable()
            .scaledToFit()
            .foregroundStyle(Color.accentColor)
        #endif
    }
}
