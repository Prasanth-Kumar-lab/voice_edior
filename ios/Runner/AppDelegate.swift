import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate {
  private let audio = AudioChannelHandler()

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    GeneratedPluginRegistrant.register(with: self)
    let launched = super.application(application, didFinishLaunchingWithOptions: launchOptions)
    if let controller = window?.rootViewController as? FlutterViewController {
      audio.register(messenger: controller.binaryMessenger)
    }
    return launched
  }
}
