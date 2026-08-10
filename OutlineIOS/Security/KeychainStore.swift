import Foundation
import Security

enum KeychainStoreError: LocalizedError {
    enum Operation: String {
        case load
        case save
        case delete
    }

    case invalidServerURL
    case encodingFailed
    case decodingFailed
    case malformedItem
    case keychain(operation: Operation, status: OSStatus)

    var errorDescription: String? {
        switch self {
        case .invalidServerURL:
            "The server URL must use HTTPS."
        case .encodingFailed:
            "The credentials could not be encoded."
        case .decodingFailed:
            "The saved credentials could not be read."
        case .malformedItem:
            "The saved credentials are invalid."
        case let .keychain(operation, status):
            "Keychain \(operation.rawValue) failed (status \(status))."
        }
    }
}

struct KeychainStore {
    private static let account = "credentials"

    private var service: String {
        Bundle.main.bundleIdentifier ?? "OutlineIOS"
    }

    func load() throws -> Credentials? {
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        switch status {
        case errSecSuccess:
            guard let data = result as? Data else {
                throw KeychainStoreError.malformedItem
            }
            let credentials: Credentials
            do {
                credentials = try JSONDecoder().decode(Credentials.self, from: data)
            } catch {
                throw KeychainStoreError.decodingFailed
            }
            guard credentials.serverURL.scheme?.lowercased() == "https" else {
                throw KeychainStoreError.invalidServerURL
            }
            return credentials
        case errSecItemNotFound:
            return nil
        default:
            throw KeychainStoreError.keychain(operation: .load, status: status)
        }
    }

    func save(_ credentials: Credentials) throws {
        guard credentials.serverURL.scheme?.lowercased() == "https" else {
            throw KeychainStoreError.invalidServerURL
        }

        let data: Data
        do {
            data = try JSONEncoder().encode(credentials)
        } catch {
            throw KeychainStoreError.encodingFailed
        }

        let query = baseQuery
        let attributes = [kSecValueData as String: data] as CFDictionary
        let updateStatus = SecItemUpdate(query as CFDictionary, attributes)
        switch updateStatus {
        case errSecSuccess:
            return
        case errSecItemNotFound:
            var addQuery = query
            addQuery[kSecValueData as String] = data
            addQuery[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
            let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
            if addStatus == errSecSuccess {
                return
            }
            if addStatus == errSecDuplicateItem {
                let retryStatus = SecItemUpdate(query as CFDictionary, attributes)
                guard retryStatus == errSecSuccess else {
                    throw KeychainStoreError.keychain(operation: .save, status: retryStatus)
                }
                return
            }
            throw KeychainStoreError.keychain(operation: .save, status: addStatus)
        default:
            throw KeychainStoreError.keychain(operation: .save, status: updateStatus)
        }
    }

    func delete() throws {
        let status = SecItemDelete(baseQuery as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainStoreError.keychain(operation: .delete, status: status)
        }
    }

    private var baseQuery: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: Self.account
        ]
    }
}
