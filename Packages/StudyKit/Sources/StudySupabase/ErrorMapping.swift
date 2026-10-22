import Foundation
import StudyData
import Supabase

/// Translates SDK and network errors into `BackendError`, so the rest of the app can decide
/// between "retry later", "sign in again" and "tell the user it was refused".
enum ErrorMapping {
    static func map(_ error: Error) -> BackendError {
        switch error {
        case let error as BackendError:
            return error
        case let error as URLError:
            return isOffline(error) ? .offline : .server(error.localizedDescription)
        case let error as PostgrestError:
            return map(postgrest: error)
        case let error as StorageError:
            return map(storageStatus: error.statusCode, message: error.message)
        case let error as FunctionsError:
            if case .httpError(let code, _) = error {
                return map(httpStatus: code, message: error.localizedDescription)
            }
            return .server(error.localizedDescription)
        case let error as AuthError:
            switch error {
            case .sessionMissing, .jwtVerificationFailed:
                return .unauthorized
            case .api(let message, _, _, let response):
                return map(httpStatus: response.statusCode, message: message)
            default:
                return .rejected(error.localizedDescription)
            }
        default:
            let nsError = error as NSError
            if nsError.domain == NSURLErrorDomain { return isOffline(URLError(URLError.Code(rawValue: nsError.code))) ? .offline : .server(nsError.localizedDescription) }
            return .server(error.localizedDescription)
        }
    }

    static func isOffline(_ error: URLError) -> Bool {
        [.notConnectedToInternet, .networkConnectionLost, .timedOut, .cannotFindHost, .cannotConnectToHost,
         .dataNotAllowed, .internationalRoamingOff, .dnsLookupFailed, .secureConnectionFailed].contains(error.code)
    }

    static func map(postgrest error: PostgrestError) -> BackendError {
        let code = error.code ?? ""
        switch code {
        case "42501":                                    // insufficient privilege / RLS violation
            return .forbidden(error.message)
        case "28000", "PGRST301", "PGRST302", "PGRST303": // not signed in / JWT invalid or expired
            return .unauthorized
        case "PGRST116":                                  // .single() found no row
            return .notFound
        case "23514", "23505", "23503", "23502", "22023", "22001", "22P02", "P0001":
            return .rejected(error.message)
        default:
            if code.hasPrefix("PGRST3") { return .unauthorized }
            if code.hasPrefix("08") || code.hasPrefix("53") || code.hasPrefix("57") { return .server(error.message) }
            return .rejected(error.message)
        }
    }

    static func map(storageStatus: String?, message: String) -> BackendError {
        map(httpStatus: Int(storageStatus ?? "") ?? 0, message: message)
    }

    static func map(httpStatus: Int, message: String) -> BackendError {
        switch httpStatus {
        case 401: .unauthorized
        case 403: .forbidden(message)
        case 404: .notFound
        case 400 where message.localizedCaseInsensitiveContains("row-level security"): .forbidden(message)
        case 400 where message.localizedCaseInsensitiveContains("not found"): .notFound
        case 400..<500: .rejected(message)
        default: .server(message)
        }
    }
}
