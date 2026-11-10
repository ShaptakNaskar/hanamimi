import Flutter
import UIKit
import AVFoundation
import CryptoKit
import ImageIO

@main
@objc class AppDelegate: FlutterAppDelegate {
  private var decodeGeneration = 0
  private let work = DispatchQueue(label: "hanamimi.media", qos: .utility)

  override func application(_ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
    GeneratedPluginRegistrant.register(with: self)
    guard let controller = window?.rootViewController as? FlutterViewController else { return false }
    let messenger = controller.binaryMessenger
    FlutterMethodChannel(name: "hanamimi/power", binaryMessenger: messenger).setMethodCallHandler { call, result in
      if call.method == "setKeepScreenOn" {
        UIApplication.shared.isIdleTimerDisabled = (call.arguments as? [String: Any])?["on"] as? Bool ?? false
      }
      result(nil)
    }
    FlutterMethodChannel(name: "hanamimi/ios_library", binaryMessenger: messenger).setMethodCallHandler { [weak self] call, result in
      guard let self = self else { return }
      let args = call.arguments as? [String: Any] ?? [:]
      if call.method == "cancelDecode" { self.decodeGeneration += 1; result(nil); return }
      let generation = self.decodeGeneration
      self.work.async {
        do {
          let path = args["path"] as? String ?? ""
          let value: Any?
          switch call.method {
          case "validate":
            let asset = AVURLAsset(url: URL(fileURLWithPath: path))
            guard asset.isPlayable, !asset.tracks(withMediaType: .audio).isEmpty,
                  asset.duration.seconds.isFinite, asset.duration.seconds > 0 else {
              throw NSError(domain: "Unsupported or corrupt audio", code: 1)
            }
            try FileManager.default.setAttributes([.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication], ofItemAtPath: path)
            value = nil
          case "scan": value = try self.scan(URL(fileURLWithPath: path))
          case "decode": value = try self.decode(path, generation: generation)
          default: DispatchQueue.main.async { result(FlutterMethodNotImplemented) }; return
          }
          DispatchQueue.main.async { result(value) }
        } catch {
          DispatchQueue.main.async { result(FlutterError(code: "media", message: error.localizedDescription, details: nil)) }
        }
      }
    }
    FlutterMethodChannel(name: "hanamimi/audio_info", binaryMessenger: messenger).setMethodCallHandler { call, result in
      if call.method == "output" {
        let session = AVAudioSession.sharedInstance()
        let port = session.currentRoute.outputs.first
        let type = port?.portType
        let route: String
        switch type {
        case .bluetoothA2DP, .bluetoothHFP, .bluetoothLE: route = "Bluetooth"
        case .headphones, .headsetMic, .lineOut: route = "Wired"
        case .usbAudio: route = "USB"
        case .airPlay: route = "AirPlay"
        default: route = "Speaker"
        }
        result(["route": route, "name": port?.portName ?? "", "sampleRate": session.sampleRate])
      } else { result(nil) }
    }
    FlutterMethodChannel(name: "hanamimi/mediastore", binaryMessenger: messenger).setMethodCallHandler { [weak self] call, result in
      guard call.method == "getAlbumArt",
            let args = call.arguments as? [String: Any], let path = args["filePath"] as? String else { result(nil); return }
      self?.work.async {
        let asset = AVURLAsset(url: URL(fileURLWithPath: path))
        var output: String? = nil
        if let item = AVMetadataItem.metadataItems(from: asset.commonMetadata, filteredByIdentifier: .commonIdentifierArtwork).first,
           let data = item.dataValue, data.count <= 16 * 1024 * 1024,
           let source = CGImageSourceCreateWithData(data as CFData, nil),
           let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
             kCGImageSourceCreateThumbnailFromImageAlways: true,
             kCGImageSourceThumbnailMaxPixelSize: 512,
             kCGImageSourceCreateThumbnailWithTransform: true] as CFDictionary) {
          let thumb = UIImage(cgImage: image)
          let id = args["albumId"] as? Int64 ?? 0
          let url = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("album-\(id).jpg")
          if let jpeg = thumb.jpegData(compressionQuality: 0.85), (try? jpeg.write(to: url, options: .atomic)) != nil { output = url.path }
        }
        let answer = output
        DispatchQueue.main.async { result(answer) }
      }
    }
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  private func identity(_ text: String) -> Int64 {
    let digest = SHA256.hash(data: Data(text.utf8))
    return digest.prefix(7).reduce(Int64(0)) { ($0 << 8) | Int64($1) }
  }

  private func scan(_ root: URL) throws -> [[String: Any]] {
    let files = try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey])
    return files.compactMap { url in
      guard let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey]),
            values.isRegularFile == true, values.isSymbolicLink != true,
            url.lastPathComponent.range(of: "^[a-f0-9]{64}--", options: .regularExpression) != nil else { return nil }
      let asset = AVURLAsset(url: url)
      guard asset.isPlayable, asset.duration.seconds.isFinite, asset.duration.seconds > 0 else { return nil }
      func tag(_ id: AVMetadataIdentifier) -> String? {
        AVMetadataItem.metadataItems(from: asset.commonMetadata, filteredByIdentifier: id).first?.stringValue
      }
      let artist = tag(.commonIdentifierArtist) ?? "Unknown artist"
      let album = tag(.commonIdentifierAlbumName) ?? "Imported music"
      return ["mediaId": identity(String(url.lastPathComponent.prefix(64))),
        "title": tag(.commonIdentifierTitle) ?? String(url.deletingPathExtension().lastPathComponent.dropFirst(66)),
        "artist": artist, "album": album, "albumId": identity(artist + "\n" + album),
        "durationMs": Int64(asset.duration.seconds * 1000), "filePath": url.path]
    }
  }

  private func decode(_ path: String, generation: Int) throws -> String {
    let asset = AVURLAsset(url: path.hasPrefix("https://") ? URL(string: path)! : URL(fileURLWithPath: path))
    guard let track = asset.tracks(withMediaType: .audio).first else { throw NSError(domain: "No audio track", code: 1) }
    let reader = try AVAssetReader(asset: asset)
    let output = AVAssetReaderAudioMixOutput(audioTracks: [track], audioSettings: [
      AVFormatIDKey: kAudioFormatLinearPCM, AVSampleRateKey: 44100,
      AVNumberOfChannelsKey: 2, AVLinearPCMBitDepthKey: 32,
      AVLinearPCMIsFloatKey: true, AVLinearPCMIsBigEndianKey: false,
      AVLinearPCMIsNonInterleaved: false])
    reader.add(output)
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("hanamimi-decode-" + UUID().uuidString + ".pcm")
    FileManager.default.createFile(atPath: url.path, contents: nil)
    let file = try FileHandle(forWritingTo: url)
    var complete = false
    defer { try? file.close(); if !complete { try? FileManager.default.removeItem(at: url) } }
    guard reader.startReading() else { throw reader.error ?? NSError(domain: "Decode failed", code: 1) }
    var size = 0
    while let sample = output.copyNextSampleBuffer() {
      let cancelled = DispatchQueue.main.sync { self.decodeGeneration != generation }
      if cancelled { reader.cancelReading(); throw NSError(domain: "Cancelled", code: 1) }
      guard let buffer = CMSampleBufferGetDataBuffer(sample) else { continue }
      let length = CMBlockBufferGetDataLength(buffer)
      size += length
      guard size <= 2 * 1024 * 1024 * 1024 else { reader.cancelReading(); throw NSError(domain: "Decoded audio exceeds 2 GiB", code: 1) }
      var data = Data(count: length)
      let status = data.withUnsafeMutableBytes { CMBlockBufferCopyDataBytes(buffer, atOffset: 0, dataLength: length, destination: $0.baseAddress!) }
      guard status == kCMBlockBufferNoErr else { throw NSError(domain: "PCM copy failed", code: 1) }
      try file.write(contentsOf: data)
    }
    guard reader.status == .completed else { throw reader.error ?? NSError(domain: "Decode failed", code: 1) }
    complete = true
    return url.path
  }
}
