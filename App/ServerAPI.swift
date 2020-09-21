import Foundation


/**
 This class represents our server.
 It performs network requests on your behalf, **encapsulating** all the technical details
 like serializing/deserializing objects for transfer over the internet
 and using the **API endpoints** implemented on the server for particular tasks.
 Whenever you want to get data from the server (e.g. the feed of posts)
 or to send data to the server (e.g. create a new post for other users to see),
 you communicate with a **shared** instance of this class.
 There is only one instance of `ServerAPI` in the app because we don't need any more.
 Such a programming pattern is called a **singleton**.
 Since all network communication is **asynchronous**
 (a network request involves sending some data to a remote computer, waiting for a response
 and then either receiving a response or timing out if the server doesn't respond in time),
 all the request methods require an additional argument, a **closure** which will be called
 when a response from the server is received and processed.
 */
class ServerAPI {
    
    static let shared = ServerAPI()
    
    
    func signUp(emailAddress: String, password: String, completion: @escaping ((User?, Error?) -> Void)) {
        let requestParameters = ["user": ["email": emailAddress, "password": password]]
        let request = makeRequest(method: .POST, endpoint: "/users.json", authorized: false, parameters: requestParameters)
        performRequest(request: request) { (result: Any?, metadata: [String : String]?, error: Error?) in
            if let userJSON = result as? [String: Any] {
                self.accessToken = metadata?["authentication_token"]
                completion(User(json: userJSON), nil)
            } else {
                completion(nil, error)
            }
        }
    }
    
    func logIn(emailAddress: String, password: String, completion: @escaping ((User?, Error?) -> Void)) {
        let requestParameters = ["user": ["email": emailAddress, "password": password]]
        let request = makeRequest(method: .POST, endpoint: "/users/authenticate.json", authorized: false, parameters: requestParameters)
        performRequest(request: request) { (result: Any?, metadata: [String : String]?, error: Error?) in
            if let userJSON = result as? [String: Any] {
                self.accessToken = metadata?["authentication_token"]
                completion(User(json: userJSON), nil)
            } else {
                completion(nil, error)
            }
        }
    }
    
    /**
     Get a batch of `Post` objects in the feed after the last `Post` object we received earlier.
     This method is supposed to be called repeatedly as the user scrolls the feed
     until they reach the last `Post`.
     */
    func getFeedPosts(startPostIndex: UInt, completion: @escaping (([Post]?, Error?) -> Void)) {
        let request = makeRequest(method: .GET, endpoint: "/posts", authorized: false, parameters: nil)
        performRequest(request: request) { (result: Any?, metadata: [String : String]?, error: Error?) in
            if let postJSONs = result as? [[String: Any]] {
                let posts = postJSONs.map { (postJSON) -> Post in
                    Post(json: postJSON)
                }
                completion(posts, nil)
            } else {
                completion(nil, error)
            }
        }
    }
    
    func getPostsOf(user: User, completion: @escaping (([Post]?, Error?) -> Void)) {
        let request = makeRequest(method: .GET, endpoint: "/users/\(user.id)/posts", authorized: false, parameters: nil)
        performRequest(request: request) { (result: Any?, metadata: [String : String]?, error: Error?) in
            if let postJSONs = result as? [[String: Any]] {
                let posts = postJSONs.map { (postJSON) -> Post in
                    Post(json: postJSON)
                }
                completion(posts, nil)
            } else {
                completion(nil, error)
            }
        }
    }
    
    func create(post: Post, completion: @escaping ((Post?, Error?) -> Void)) {
        let requestParameters = ["post": [
            "location": nil,
            "description": post.text,
            "image": post.images!.first?.url.absoluteString,
            ]]
        let request = makeRequest(method: .POST, endpoint: "/posts.json", authorized: true, parameters: requestParameters)
        performRequest(request: request) { (result: Any?, metadata: [String : String]?, error: Error?) in
            if let postJSON = result as? [String: Any] {
                completion(Post(json: postJSON), nil)
            } else {
                completion(nil, error)
            }
        }
    }
    
    // MARK: - Private stuff
    
    /**
     HTTP methods, as defined in https://www.w3.org/Protocols/rfc2616/rfc2616-sec9.html
     We only use some of them, the rest are provided for completeness' sake.
     */
    enum HTTPMethod: String {
        case OPTIONS
        case GET
        case HEAD
        case POST
        case PUT
        case DELETE
        case TRACE
        case CONNECT
        case PATCH
    }
    
    private let baseURLString: String
    private var session: URLSession
    private var accessToken: String? {
        didSet {
            UserDefaults.standard.set(accessToken, forKey: "access token")
        }
    }
    
    private init() {
        // It is always a good idea to provide a meaningful 'User-Agent' HTTP header value
        let appInfoDictionary = Bundle.main.infoDictionary!
        let appName = appInfoDictionary[kCFBundleNameKey as String]!
        let appVersion = appInfoDictionary["CFBundleShortVersionString"]!
        let userAgentString = "\(appName)/\(appVersion) iOS/\(ProcessInfo().operatingSystemVersionString)"
        
        let config = URLSessionConfiguration.ephemeral
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 300
        config.networkServiceType = .default
        config.allowsCellularAccess = true
        config.connectionProxyDictionary = CFNetworkCopySystemProxySettings()?.takeRetainedValue() as [NSObject : AnyObject]?
        config.tlsMinimumSupportedProtocolVersion = .TLSv12
        config.httpShouldUsePipelining = true
        config.httpShouldSetCookies = false
        config.httpCookieAcceptPolicy = .never
        config.httpAdditionalHeaders = ["User-Agent": userAgentString, "Accept": "application/json"]
        config.httpMaximumConnectionsPerHost = 1
        config.httpCookieStorage = nil
        config.urlCache = nil
        if ProcessInfo().arguments.contains("mock-api") {
            config.protocolClasses = [MockURLProtocol.self]
            baseURLString = "mock://api.example.com"
        } else {
            baseURLString = "http://130.193.44.149:3000"
        }
        
        let sessionDelegateQueue = OperationQueue()
        sessionDelegateQueue.name = "API.HTTP"
        sessionDelegateQueue.maxConcurrentOperationCount = 1
        
        session = URLSession(configuration: config, delegate: nil, delegateQueue: sessionDelegateQueue)
        
        accessToken = UserDefaults.standard.string(forKey: "access token")
    }
    
    /**
     Compose a URLRequest object
     */
    private func makeRequest(method: HTTPMethod, endpoint: String, authorized: Bool, parameters: [String: Any]?) -> URLRequest {
        guard let url = URL(string: baseURLString + endpoint) else {
            fatalError("Invalid endpoint: \(endpoint)")
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = method.rawValue
        if let json = parameters {
            request.httpBody = try! JSONSerialization.data(withJSONObject: json, options: [])
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        if authorized && accessToken != nil {
            request.setValue(accessToken!, forHTTPHeaderField: "Authentication-Token")
        }
        return request
    }
    
    /**
     Perform a network request and process a server's response
     */
    private func performRequest(request: URLRequest, completion: @escaping ((_ data: Any?, _ metadata: [String: String]?, _ error: Error?) -> Void)) {
        let task = session.dataTask(with: request) { (jsonData: Data?, urlResponse: URLResponse?, requestError: Error?) in
            var result: Any?
            var metadata: [String: String]?
            var reportedError = requestError
            if requestError == nil && jsonData != nil {
                do {
                    let json = try JSONSerialization.jsonObject(with: jsonData!, options: [])
                    if let formattedJSONData = try? JSONSerialization.data(withJSONObject: json, options: [.prettyPrinted, .withoutEscapingSlashes]) {
                        if let formattedJSONString = String(data: formattedJSONData, encoding: .utf8) {
                            print("\(request.httpMethod!) \(request.url!) returned status code \((urlResponse as! HTTPURLResponse).statusCode) \(formattedJSONString)")
                        }
                    }
                    
                    if let responseJSON = (json as? [String: Any]) {
                        result = responseJSON["data"]
                        metadata = responseJSON["meta"] as? [String: String]
                        if result == nil {
                            if let firstErrorInfo = (responseJSON["errors"] as? [[String: Any]])?.first {
                                reportedError = NSError(domain: "API", code: 1, userInfo: [NSLocalizedDescriptionKey: firstErrorInfo["detail"] as? String ?? "Unknown"])
                            }
                        }
                    }
                } catch {
                    print("Could not decode JSON: \(error)")
                    reportedError = error
                }
            }
            DispatchQueue.main.async {
                completion(result, metadata, reportedError)
            }
        }
        task.resume()
    }
}


// MARK: - Model Object JSON Decoders


extension User {
    convenience init(json: [String: Any]) {
        #warning("Remove the default name")
        let userName = json["full_name"] as? String ?? "NO NAME"
        let emailAddress = json["email"] as! String
        self.init(name: userName, emailAddress: emailAddress)
        id = json["id"] as! Int
        if let userAvatarURI = json["portrait"] as? String {
            if let userAvatarURL = URL(string: userAvatarURI) {
                self.avatar = Image(url: userAvatarURL)
            }
        }
        self.bio = json["bio"] as? String
    }
}


extension Post {
    convenience init(json: [String: Any]) {
        let date = Date(timeIntervalSince1970: TimeInterval(json["created_at"] as! Int))
        let user = User(json: json["user"] as! [String : Any])
        let text = json["description"] as! String
        var images: [Image]?
        if let imageURL = URL(string: json["image"] as! String) {
            images = [Image(url: imageURL)]
        }
        self.init(date: date, author: user, text: text, images: images, video: nil)
        id = json["id"] as! Int
    }
}


extension Image {
    convenience init(json: [String: Any]) {
        let imageURI = json["url"] as! String
        self.init(url: URL(string: imageURI)!)
    }
}