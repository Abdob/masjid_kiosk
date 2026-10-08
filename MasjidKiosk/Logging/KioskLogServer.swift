import Foundation
import Network
import Darwin

/// Serves the kiosk's day logs over HTTP on the masjid's network.
///
/// This exists because the alternative — copying the file out of the app's
/// container — needs a Mac, Xcode, a paired device and someone to unlock the
/// iPad. The kiosk is a wall-mounted iPad locked in Guided Access, so the
/// practical way to collect a log is to ask it for one:
///
///     curl -u admin:admin http://<ipad-ip>:8080/log -O
///
/// Nothing is required on the iPad, and any machine with `curl` will do.
/// The listener only runs while the app is in the foreground, which for this
/// kiosk is always — Guided Access guarantees it.
///
/// Read-only by design: it serves this app's own `kiosk-log-YYYY-MM-DD.csv`
/// files and nothing else, so a crafted path cannot reach anything private.
final class KioskLogServer {

    static let shared = KioskLogServer()

    private let queue = DispatchQueue(label: "kiosk.logserver")
    private var listener: NWListener?

    private init() {}

    /// Begin listening. Safe to call more than once.
    func start() {
        guard KioskConfig.isLogServerEnabled, listener == nil else { return }
        guard let port = NWEndpoint.Port(rawValue: KioskConfig.logServerPort) else { return }

        let parameters = NWParameters.tcp
        parameters.allowLocalEndpointReuse = true
        guard let listener = try? NWListener(using: parameters, on: port) else {
            NSLog("KioskLogServer: could not listen on port \(KioskConfig.logServerPort)")
            return
        }

        listener.stateUpdateHandler = { state in
            switch state {
            case .ready:
                NSLog("KioskLogServer: ready at \(KioskLogServer.downloadURL() ?? "port \(KioskConfig.logServerPort)")")
            case .failed(let error):
                NSLog("KioskLogServer: failed — \(error.localizedDescription)")
            default:
                break
            }
        }
        listener.newConnectionHandler = { [weak self] connection in
            self?.accept(connection)
        }
        listener.start(queue: queue)
        self.listener = listener
    }

    // MARK: - Connections

    private func accept(_ connection: NWConnection) {
        connection.start(queue: queue)
        receive(on: connection, buffer: Data())
    }

    /// Read until the end of the request head. These are all GETs with no
    /// body, so the blank line after the headers is the whole request.
    private func receive(on connection: NWConnection, buffer: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 8192) { [weak self] chunk, _, isComplete, error in
            guard let self else { return }
            var buffer = buffer
            if let chunk { buffer.append(chunk) }

            if let range = buffer.range(of: Data("\r\n\r\n".utf8)) {
                let head = String(decoding: buffer[..<range.lowerBound], as: UTF8.self)
                self.respond(to: head, on: connection)
                return
            }
            // A request head this long is not one of ours.
            guard error == nil, !isComplete, buffer.count < 8192 else {
                connection.cancel()
                return
            }
            self.receive(on: connection, buffer: buffer)
        }
    }

    private func respond(to head: String, on connection: NWConnection) {
        let lines = head.split(separator: "\r\n", omittingEmptySubsequences: false).map(String.init)
        let request = lines.first?.split(separator: " ").map(String.init) ?? []
        let method = request.first ?? ""
        let path = request.count > 1 ? request[1] : "/"

        guard isAuthorized(lines) else {
            send(.unauthorized, on: connection)
            return
        }
        guard method == "GET" || method == "HEAD" else {
            send(.plain(status: "405 Method Not Allowed", body: "Only GET is supported.\n"), on: connection)
            return
        }

        // KioskLog is an actor, so reading it is async; the connection stays
        // open until the answer is ready.
        Task {
            let response = await self.response(for: path)
            self.send(response, on: connection)
        }
    }

    private func response(for path: String) async -> Response {
        // Strip any query string; none of these routes take parameters.
        let route = path.split(separator: "?").first.map(String.init) ?? "/"

        switch route {
        case "/", "/index.html":
            return .html(await index())

        case "/logs":
            let names = await KioskLog.shared.fileNames()
            return .plain(status: "200 OK", body: names.joined(separator: "\n") + "\n")

        case "/status":
            // What staff need when a day "doesn't show": is the kiosk
            // recording, and what does *it* think today's date is? The
            // filename follows the iPad's clock, which need not agree with
            // the clock on the machine doing the fetching.
            let names = await KioskLog.shared.fileNames()
            let tally = await KioskLog.shared.todaysTally()
            let readerReady = await SquareReader.shared.isReady
            let body = """
            today=\(Self.todayString())
            logs=\(names.count)
            rows_today=\(tally?.rows ?? 0)
            reader_ready=\(readerReady)

            """
            return .plain(status: "200 OK", body: body)

        case "/log":
            // Today's log, the common case.
            let today = Self.todayString()
            guard let data = await KioskLog.shared.contents(of: today) else {
                return .plain(status: "404 Not Found", body: "No log for \(today) yet.\n")
            }
            return .csv(data, name: KioskLog.resolve(today) ?? "kiosk-log.csv")

        default:
            guard route.hasPrefix("/log/") else {
                return .plain(status: "404 Not Found", body: "Not found.\n")
            }
            let requested = String(route.dropFirst("/log/".count))
            guard let name = KioskLog.resolve(requested),
                  let data = await KioskLog.shared.contents(of: requested) else {
                return .plain(status: "404 Not Found", body: "No log for \(requested).\n")
            }
            return .csv(data, name: name)
        }
    }

    /// A plain page, so a browser pointed at the kiosk is useful too.
    private func index() async -> String {
        let names = await KioskLog.shared.fileNames()
        let items = names.isEmpty
            ? "<li>No logs yet.</li>"
            : names.map { "<li><a href=\"/log/\($0)\">\($0)</a></li>" }.joined()
        return """
        <!doctype html><html><head><meta charset="utf-8">
        <title>Masjid kiosk logs</title>
        <style>body{font:16px -apple-system,sans-serif;margin:2rem;max-width:40rem}
        li{margin:.3rem 0}</style></head><body>
        <h1>Masjid kiosk logs</h1>
        <p>Today: <a href="/log">/log</a></p>
        <ul>\(items)</ul>
        </body></html>
        """
    }

    // MARK: - Auth

    private func isAuthorized(_ headerLines: [String]) -> Bool {
        let expected = Data("\(KioskConfig.logServerUser):\(KioskConfig.logServerPassword)".utf8)
            .base64EncodedString()
        for line in headerLines {
            let parts = line.split(separator: ":", maxSplits: 1).map(String.init)
            guard parts.count == 2, parts[0].lowercased() == "authorization" else { continue }
            let value = parts[1].trimmingCharacters(in: .whitespaces)
            guard value.lowercased().hasPrefix("basic ") else { return false }
            return String(value.dropFirst("basic ".count)) == expected
        }
        return false
    }

    // MARK: - Responses

    private enum Response {
        case plain(status: String, body: String)
        case html(String)
        case csv(Data, name: String)
        case unauthorized
    }

    private func send(_ response: Response, on connection: NWConnection) {
        var status = "200 OK"
        var headers = ["Connection: close"]
        var body = Data()

        switch response {
        case .plain(let responseStatus, let text):
            status = responseStatus
            headers.append("Content-Type: text/plain; charset=utf-8")
            body = Data(text.utf8)

        case .html(let html):
            headers.append("Content-Type: text/html; charset=utf-8")
            body = Data(html.utf8)

        case .csv(let data, let name):
            headers.append("Content-Type: text/csv; charset=utf-8")
            headers.append("Content-Disposition: attachment; filename=\"\(name)\"")
            body = data

        case .unauthorized:
            status = "401 Unauthorized"
            headers.append("WWW-Authenticate: Basic realm=\"Masjid kiosk logs\"")
            headers.append("Content-Type: text/plain; charset=utf-8")
            body = Data("Authentication required.\n".utf8)
        }

        headers.append("Content-Length: \(body.count)")
        let head = "HTTP/1.1 \(status)\r\n" + headers.joined(separator: "\r\n") + "\r\n\r\n"
        var message = Data(head.utf8)
        message.append(body)

        connection.send(content: message, completion: .contentProcessed { _ in
            connection.cancel()
        })
    }

    // MARK: - Where to point curl

    /// The address staff should use, shown on the staff page.
    static func downloadURL() -> String? {
        guard let ip = wifiAddress() else { return nil }
        return "http://\(ip):\(KioskConfig.logServerPort)/log"
    }

    /// The iPad's IPv4 address on Wi-Fi.
    static func wifiAddress() -> String? {
        var addresses: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&addresses) == 0, let first = addresses else { return nil }
        defer { freeifaddrs(addresses) }

        for pointer in sequence(first: first, next: { $0.pointee.ifa_next }) {
            let interface = pointer.pointee
            guard let address = interface.ifa_addr,
                  address.pointee.sa_family == UInt8(AF_INET),
                  String(cString: interface.ifa_name) == "en0" else { continue }

            var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            guard getnameinfo(address, socklen_t(address.pointee.sa_len),
                              &hostname, socklen_t(hostname.count),
                              nil, 0, NI_NUMERICHOST) == 0 else { continue }
            return String(cString: hostname)
        }
        return nil
    }

    private static func todayString() -> String {
        let day = DateFormatter()
        day.calendar = Calendar(identifier: .gregorian)
        day.locale = Locale(identifier: "en_US_POSIX")
        day.dateFormat = "yyyy-MM-dd"
        return day.string(from: Date())
    }
}
