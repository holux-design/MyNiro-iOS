import Foundation

/// URLSession delegate that refuses HTTP redirects.
/// Kia/Hyundai EU IDPConnect signin returns 302 with `?code=` in the
/// `Location` header. Following that redirect hits the CCAPI host and
/// triggers WAF "400 … classified as an abusing request".
final class NoRedirectDelegate: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping (URLRequest?) -> Void
    ) {
        completionHandler(nil)
    }
}

enum EUAuthSession {
    private static let delegate = NoRedirectDelegate()

    /// Shares `HTTPCookieStorage.shared` with `.shared` so authorize cookies
    /// are visible to the no-redirect signin POST.
    static let noRedirect: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.httpCookieStorage = HTTPCookieStorage.shared
        config.httpCookieAcceptPolicy = .always
        config.httpShouldSetCookies = true
        return URLSession(configuration: config, delegate: delegate, delegateQueue: nil)
    }()
}
