import Foundation
import EventCore

/// One credential entry point for both extraction and the settings sheet.
/// The Hammerspoon file is a development-only source and is never copied into the app.
enum OpenRouterCredential {
    static var developmentFileURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".config/send-to-hammerspoon/openrouter-api-key")
    }

    static func read() throws -> String {
        try read(fileURL: developmentFileURL, fallback: Keychain.read)
    }

    static func read(fileURL: URL, fallback: () throws -> String) throws -> String {
        let files = FileManager.default
        guard files.fileExists(atPath: fileURL.path) else { return try fallback() }

        do {
            let attributes = try files.attributesOfItem(atPath: fileURL.path)
            guard attributes[.type] as? FileAttributeType == .typeRegular,
                  let permissions = attributes[.posixPermissions] as? NSNumber,
                  permissions.intValue & 0o077 == 0,
                  let size = attributes[.size] as? NSNumber,
                  (1...4096).contains(size.intValue) else {
                throw DraftError("Die lokale OpenRouter-Schlüsseldatei muss eine kleine, nur für deinen Benutzer lesbare Datei sein (chmod 600).")
            }

            let data = try Data(contentsOf: fileURL)
            guard data.count <= 4096,
                  let key = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !key.isEmpty,
                  !key.contains(where: { $0.isWhitespace || $0 == "\0" }) else {
                throw DraftError("Die lokale OpenRouter-Schlüsseldatei enthält keinen gültigen Schlüssel.")
            }
            return key
        } catch let error as DraftError {
            throw error
        } catch {
            throw DraftError("Die lokale OpenRouter-Schlüsseldatei konnte nicht gelesen werden. Bitte Dateirechte prüfen.")
        }
    }
}
