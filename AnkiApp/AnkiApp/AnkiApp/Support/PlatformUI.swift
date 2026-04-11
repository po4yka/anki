import SwiftUI

#if os(macOS)
import AppKit
typealias PlatformImage = NSImage
#elseif os(iOS)
import UIKit
typealias PlatformImage = UIImage
#endif

struct PlatformImageView: View {
    let image: PlatformImage

    var body: some View {
        #if os(macOS)
        Image(nsImage: image)
            .resizable()
        #else
        Image(uiImage: image)
            .resizable()
        #endif
    }
}

struct AppIconView: View {
    var body: some View {
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
