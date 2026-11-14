import Foundation

struct CockpitOAuthAttempt: Hashable {
    let authorizationURL: URL
    let callbackScheme: String
    let callbackHost: String
    let callbackPort: Int
    let callbackPath: String
    let state: String
}

struct CockpitOAuthCallback: Identifiable, Hashable {
    let url: URL

    var id: URL { url }
}

enum CockpitOAuthCallbackInspection: Equatable {
    case notCallback
    case captured(CockpitOAuthCallback)
    case rejected(CockpitOAuthRelayError)
}

enum CockpitOAuthRelayError: String, Error, Equatable {
    case invalidAuthorizationURL
    case unsupportedAuthorizationURL
    case invalidHostedAuthorizationURL
    case invalidAuthorizationParameters
    case invalidRedirectURI
    case invalidCallback
    case callbackMismatch
    case stateMismatch

    var localizationKey: String {
        "oauth.relay.error.\(rawValue)"
    }
}

enum CockpitOAuthRelay {
    static func prepare(_ rawURL: String) throws -> CockpitOAuthAttempt {
        let trimmedURL = rawURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard
            !trimmedURL.isEmpty,
            let suppliedURL = URL(string: trimmedURL),
            let suppliedComponents = URLComponents(url: suppliedURL, resolvingAgainstBaseURL: false)
        else {
            throw CockpitOAuthRelayError.invalidAuthorizationURL
        }

        let innerURL: URL
        if isHostedAuthorizationURL(suppliedComponents) {
            let authorizeURL = try requiredValue(
                named: "authorize_url",
                in: suppliedComponents.queryItems,
                error: .invalidHostedAuthorizationURL
            )
            guard let parsedInnerURL = URL(string: authorizeURL) else {
                throw CockpitOAuthRelayError.invalidHostedAuthorizationURL
            }
            innerURL = parsedInnerURL
        } else {
            innerURL = suppliedURL
        }

        guard
            let authorizationComponents = URLComponents(url: innerURL, resolvingAgainstBaseURL: false),
            isDirectAuthorizationURL(authorizationComponents)
        else {
            throw CockpitOAuthRelayError.unsupportedAuthorizationURL
        }

        let queryItems = authorizationComponents.queryItems
        let clientID = try requiredValue(named: "client_id", in: queryItems)
        let responseType = try requiredValue(named: "response_type", in: queryItems)
        let redirectValue = try requiredValue(named: "redirect_uri", in: queryItems)
        let state = try requiredValue(named: "state", in: queryItems)
        let codeChallenge = try requiredValue(named: "code_challenge", in: queryItems)
        let challengeMethod = try requiredValue(named: "code_challenge_method", in: queryItems)

        guard
            !clientID.isEmpty,
            responseType == "code",
            !state.isEmpty,
            !codeChallenge.isEmpty,
            challengeMethod == "S256"
        else {
            throw CockpitOAuthRelayError.invalidAuthorizationParameters
        }

        let callback = try callbackComponents(from: redirectValue)
        return CockpitOAuthAttempt(
            authorizationURL: suppliedURL,
            callbackScheme: "http",
            callbackHost: callback.host,
            callbackPort: callback.port,
            callbackPath: "/auth/callback",
            state: state
        )
    }

    static func inspectCallback(
        _ url: URL,
        for attempt: CockpitOAuthAttempt
    ) -> CockpitOAuthCallbackInspection {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return .notCallback
        }

        let host = components.host?.lowercased()
        let isLoopbackNavigation = host == "localhost" || host == "127.0.0.1"
        let resemblesCallback = isLoopbackNavigation || components.path == "/auth/callback"
        guard resemblesCallback else {
            return .notCallback
        }

        guard
            components.scheme?.lowercased() == attempt.callbackScheme,
            host == attempt.callbackHost,
            components.port == attempt.callbackPort,
            components.path == attempt.callbackPath,
            !hasCredentials(components),
            components.fragment == nil
        else {
            return .rejected(.callbackMismatch)
        }

        let codeItems = (components.queryItems ?? []).filter { $0.name == "code" }
        let stateItems = (components.queryItems ?? []).filter { $0.name == "state" }
        guard
            codeItems.count == 1,
            let code = codeItems[0].value,
            !code.isEmpty,
            stateItems.count == 1,
            let returnedState = stateItems[0].value,
            !returnedState.isEmpty
        else {
            return .rejected(.invalidCallback)
        }

        guard constantTimeEqual(returnedState, attempt.state) else {
            return .rejected(.stateMismatch)
        }
        return .captured(CockpitOAuthCallback(url: url))
    }

    private static func isHostedAuthorizationURL(_ components: URLComponents) -> Bool {
        components.scheme?.lowercased() == "https"
            && components.host?.lowercased() == "chatgpt.com"
            && components.port == nil
            && components.path == "/codex/desktop-auth"
            && !hasCredentials(components)
            && components.fragment == nil
    }

    private static func isDirectAuthorizationURL(_ components: URLComponents) -> Bool {
        components.scheme?.lowercased() == "https"
            && components.host?.lowercased() == "auth.openai.com"
            && components.port == nil
            && components.path == "/oauth/authorize"
            && !hasCredentials(components)
            && components.fragment == nil
    }

    private static func requiredValue(
        named name: String,
        in queryItems: [URLQueryItem]?,
        error: CockpitOAuthRelayError = .invalidAuthorizationParameters
    ) throws -> String {
        let matches = (queryItems ?? []).filter { $0.name == name }
        guard matches.count == 1, let value = matches[0].value, !value.isEmpty else {
            throw error
        }
        return value
    }

    private static func callbackComponents(from redirectValue: String) throws -> (host: String, port: Int) {
        guard
            let redirectURL = URL(string: redirectValue),
            let components = URLComponents(url: redirectURL, resolvingAgainstBaseURL: false),
            components.scheme?.lowercased() == "http",
            let host = components.host?.lowercased(),
            host == "localhost" || host == "127.0.0.1",
            let port = components.port,
            (1...65_535).contains(port),
            components.path == "/auth/callback",
            !hasCredentials(components),
            components.percentEncodedQuery == nil,
            components.fragment == nil
        else {
            throw CockpitOAuthRelayError.invalidRedirectURI
        }
        return (host, port)
    }

    private static func hasCredentials(_ components: URLComponents) -> Bool {
        components.user != nil || components.password != nil
    }

    private static func constantTimeEqual(_ lhs: String, _ rhs: String) -> Bool {
        let left = Array(lhs.utf8)
        let right = Array(rhs.utf8)
        let count = max(left.count, right.count)
        var difference = left.count ^ right.count

        for index in 0..<count {
            let leftByte = index < left.count ? left[index] : 0
            let rightByte = index < right.count ? right[index] : 0
            difference |= Int(leftByte ^ rightByte)
        }
        return difference == 0
    }
}
