import Flutter
import UIKit

private let pasteboardStickerPackType = "net.whatsapp.third-party.sticker-pack"

struct WhatsAppStickerExporter {
    static func isInstalled() -> Bool {
        guard let url = URL(string: "whatsapp://") else { return false }
        return UIApplication.shared.canOpenURL(url)
    }

    static func addPack(_ args: [String: Any], completion: @escaping (Bool) -> Void) {
        guard
            let packId = args["id"] as? String,
            let name = args["name"] as? String,
            let publisher = args["publisher"] as? String,
            let trayIconPath = args["trayIconPath"] as? String,
            let stickers = args["stickers"] as? [[String: Any]]
        else {
            completion(false)
            return
        }

        guard let trayData = FileManager.default.contents(atPath: trayIconPath) else {
            completion(false)
            return
        }

        var stickerJson: [[String: Any]] = []
        for sticker in stickers {
            guard let filePath = sticker["filePath"] as? String,
                  let data = FileManager.default.contents(atPath: filePath) else { continue }
            stickerJson.append([
                "image_data": data.base64EncodedString(),
                "emojis": [],
            ])
        }
        guard !stickerJson.isEmpty else {
            completion(false)
            return
        }

        let packJson: [String: Any] = [
            "identifier": packId,
            "name": name,
            "publisher": publisher,
            "tray_image": trayData.base64EncodedString(),
            "stickers": stickerJson,
        ]
        guard let packData = try? JSONSerialization.data(withJSONObject: packJson) else {
            completion(false)
            return
        }

        UIPasteboard.general.setItems(
            [[pasteboardStickerPackType: packData]],
            options: [
                .localOnly: true,
                .expirationDate: Date().addingTimeInterval(60),
            ]
        )

        guard let url = URL(string: "whatsapp://stickerPack") else {
            completion(false)
            return
        }
        UIApplication.shared.open(url) { success in completion(success) }
    }
}

@main
@objc class AppDelegate: FlutterAppDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    GeneratedPluginRegistrant.register(with: self)

    let controller = window?.rootViewController as! FlutterViewController
    let channel = FlutterMethodChannel(name: "sticker_creator/whatsapp", binaryMessenger: controller.binaryMessenger)
    channel.setMethodCallHandler { call, result in
      switch call.method {
      case "isWhatsAppInstalled":
        result(WhatsAppStickerExporter.isInstalled())
      case "addPack":
        guard let args = call.arguments as? [String: Any] else {
          result(FlutterError(code: "bad_args", message: "Expected a map", details: nil))
          return
        }
        WhatsAppStickerExporter.addPack(args) { success in
          result(success)
        }
      default:
        result(FlutterMethodNotImplemented)
      }
    }

    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }
}
