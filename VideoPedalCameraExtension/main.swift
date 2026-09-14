import Foundation
import CoreMediaIO
import CoreMedia
import CoreVideo

let providerSource = CameraExtensionProviderSource(clientQueue: nil)
CMIOExtensionProvider.startService(provider: providerSource.provider)
CFRunLoopRun()
