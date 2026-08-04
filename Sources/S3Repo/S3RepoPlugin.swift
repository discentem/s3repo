//
//  S3RepoPlugin.swift
//  munki
//
//  Created for S3 bucket repository support
//
//  Licensed under the Apache License, Version 2.0 (the "License");
//  you may not use this file except in compliance with the License.
//  You may obtain a copy of the License at
//
//       https://www.apache.org/licenses/LICENSE-2.0
//
//  Unless required by applicable law or agreed to in writing, software
//  distributed under the License is distributed on an "AS IS" BASIS,
//  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
//  See the License for the specific language governing permissions and
//  limitations under the License.

import Foundation
import AWSS3
import AWSClientRuntime
import AWSConfig

// MARK: - Logging Helper

func logDebug(_ message: String) {
    let timestamp = DateFormatter().then {
        $0.dateFormat = "HH:mm:ss.SSS"
    }.string(from: Date())
    fputs("[S3Repo] [\(timestamp)] \(message)\n", stderr)
    fflush(stderr)
}

extension DateFormatter {
    func then(_ block: (Self) -> Void) -> Self {
        block(self)
        return self
    }
}

/// S3 Bucket implementation of the Repo protocol
public class S3Repo: Repo {
    private let s3Client: S3Client
    private let bucket: String
    private let prefix: String
    private let isLocalEndpoint: Bool
    
    /// Initialize S3 Repo with S3 URL (protocol requirement)
    public required convenience init(_ url: String) throws {
        try self.init(url, awsConfig: nil)
    }
    
    /// Initialize S3 Repo with S3 URL and optional AWS configuration
    /// Supports:
    ///   - s3://bucket/path/to/repo (uses AWS S3)
    ///   - http://endpoint/bucket/path/to/repo (S3 emulator via HTTP)
    ///   - https://endpoint/bucket/path/to/repo (S3 emulator via HTTPS)
    /// - Parameters:
    ///   - url: S3 URL in one of the supported formats
    ///   - awsConfig: Optional AWSConfig for additional configuration
    public init(_ url: String, awsConfig: AWSConfig? = nil) throws {
        logDebug("S3Repo.init() called with URL: \(url)")
        
        let (bucket, prefix, endpointURL) = try Self.parseURL(url)
        logDebug("Parsed URL - bucket: \(bucket), prefix: \(prefix), endpoint: \(endpointURL ?? "nil")")
        
        self.bucket = bucket
        self.prefix = prefix
        
        // Determine if using local endpoint (HTTP/HTTPS, not AWS S3)
        self.isLocalEndpoint = endpointURL != nil
        
        // Use endpoint from URL if present, otherwise from awsConfig
        let resolvedEndpoint = endpointURL ?? awsConfig?.endpoint
        
        // Initialize S3 client
        logDebug("Creating S3Client config...")
        var config = try S3Client.S3ClientConfig()
        logDebug("S3ClientConfig created successfully")
        
        // Always set region - use AWS_REGION env var, config, or default to us-east-1
        let region = awsConfig?.region ?? ProcessInfo.processInfo.environment["AWS_REGION"] ?? "us-east-1"
        config.region = region
        logDebug("Region set to: \(region)")
        
        if let endpoint = resolvedEndpoint {
            config.endpoint = endpoint
            // Force path-style addressing (bucket in path, not subdomain) for local
            // S3-compatible endpoints (rustfs, MinIO, etc.) - matches AWSConfig.createS3Client().
            if endpoint.lowercased().hasPrefix("http://") || endpoint.lowercased().hasPrefix("https://") {
                config.forcePathStyle = true
            }
            logDebug("Endpoint configured: \(endpoint), forcePathStyle=\(config.forcePathStyle ?? false)")
        }
        
        logDebug("Creating S3Client...")
        self.s3Client = S3Client(config: config)
        logDebug("S3Client created successfully")
    }
    

    
    /// List all items of a specific kind (subdirectory) in the S3 bucket
    public func list(_ kind: String) async throws -> [String] {
        logDebug("list() called with kind: \(kind)")
        let listPath = prefix.isEmpty ? kind : "\(prefix)/\(kind)"
        let prefix = listPath.isEmpty ? "" : "\(listPath)/"
        logDebug("Listing with prefix: \(prefix)")
        
        var allKeys: [String] = []
        var continuationToken: String?
        var pageCount = 0
        
        repeat {
            pageCount += 1
            logDebug("Fetching page \(pageCount) from S3...")
            
            let input = ListObjectsV2Input(
                bucket: bucket,
                continuationToken: continuationToken,
                delimiter: "/",
                prefix: prefix.isEmpty ? nil : prefix
            )
            
            let output = try await s3Client.listObjectsV2(input: input)
            logDebug("Page \(pageCount) returned successfully")
            
            if let contents = output.contents {
                logDebug("Page \(pageCount) has \(contents.count) objects")
                for object in contents {
                    if let key = object.key {
                        // Extract just the filename/identifier
                        let filename = key.replacingOccurrences(of: prefix, with: "")
                        if !filename.isEmpty {
                            allKeys.append(filename)
                            logDebug("Added key: \(filename)")
                        }
                    }
                }
            } else {
                logDebug("Page \(pageCount) has no contents")
            }
            
            continuationToken = output.nextContinuationToken
            if continuationToken != nil {
                logDebug("More pages available, continuing...")
            }
        } while continuationToken != nil
        
        logDebug("list() returning \(allKeys.count) items")
        return allKeys
    }
    
    /// Get object data from S3
    public func get(_ identifier: String) async throws -> Data {
        logDebug("get() called for identifier: \(identifier)")
        let key = fullKey(for: identifier)
        logDebug("Fetching S3 object with key: \(key)")
        
        let input = GetObjectInput(bucket: bucket, key: key)
        let output = try await s3Client.getObject(input: input)
        logDebug("S3 getObject completed successfully")
        
        guard let body = output.body else {
            logDebug("ERROR: No body in S3 response for \(identifier)")
            throw S3RepoError.noData("No data returned for object: \(identifier)")
        }
        
        // Read the stream into Data
        logDebug("Reading data from S3 stream...")
        let data = try await body.readData() ?? Data()
        logDebug("Data read successfully, size: \(data.count) bytes")
        
        return data
    }
    
    /// Get object from S3 and save to local file
    public func get(_ identifier: String, toFile localFilePath: String) async throws {
        let data = try await get(identifier)
        try data.write(to: URL(fileURLWithPath: localFilePath))
    }
    
    /// Put Data object to S3
    public func put(_ identifier: String, content: Data) async throws {
        logDebug("put() called for identifier: \(identifier), size: \(content.count) bytes")
        let key = fullKey(for: identifier)
        logDebug("Uploading to S3 with key: \(key)")
        
        let input = PutObjectInput(
            body: .data(content),
            bucket: bucket,
            key: key
        )
        
        logDebug("Calling S3 putObject...")
        _ = try await s3Client.putObject(input: input)
        logDebug("S3 putObject completed successfully")
    }
    
    /// Put file from local path to S3
    public func put(_ identifier: String, fromFile localFilePath: String) async throws {
        let fileURL = URL(fileURLWithPath: localFilePath)
        let data = try Data(contentsOf: fileURL)
        try await put(identifier, content: data)
    }
    
    /// Delete object from S3
    public func delete(_ identifier: String) async throws {
        logDebug("delete() called for identifier: \(identifier)")
        let key = fullKey(for: identifier)
        logDebug("Deleting S3 object with key: \(key)")
        
        let input = DeleteObjectInput(bucket: bucket, key: key)
        logDebug("Calling S3 deleteObject...")
        _ = try await s3Client.deleteObject(input: input)
        logDebug("S3 deleteObject completed successfully")
    }
    
    /// Get the S3 path for an identifier
    public func pathFor(_ identifier: String) -> String? {
        let key = fullKey(for: identifier)
        return "s3://\(bucket)/\(key)"
    }
    
    // MARK: - Private Helpers
    
    /// Parse S3 URL to extract bucket, prefix, and optional endpoint
    /// - Parameter url: URL string in one of these formats:
    ///   - s3://bucket/path/to/repo (AWS S3)
    ///   - http(s)://endpoint/bucket/path/to/repo (S3 emulator)
    /// - Returns: Tuple containing (bucket, prefix, endpoint)
    static func parseURL(_ url: String) throws -> (bucket: String, prefix: String, endpoint: String?) {
        // Determine if this is an S3 URL or a direct endpoint URL
        if url.hasPrefix("s3://") {
            // Standard S3 URL: s3://bucket/path/to/repo
            guard let components = URLComponents(string: url),
                  let bucketName = components.host else {
                throw S3RepoError.invalidURL("Invalid S3 URL: \(url)")
            }
            let bucket = bucketName
            let prefix = components.path.isEmpty ? "" : components.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            return (bucket, prefix, nil)
        } else if url.hasPrefix("http://") || url.hasPrefix("https://") {
            // Direct endpoint URL: http(s)://endpoint/bucket/path/to/repo
            guard let components = URLComponents(string: url) else {
                throw S3RepoError.invalidURL("Invalid endpoint URL: \(url)")
            }
            
            // Extract endpoint (scheme + host + port)
            var endpoint = components.scheme ?? ""
            endpoint += "://" + (components.host ?? "")
            if let port = components.port {
                endpoint += ":\(port)"
            }
            
            // Parse path to extract bucket and prefix
            let pathComponents = components.path.split(separator: "/", omittingEmptySubsequences: true)
            guard pathComponents.count >= 1 else {
                throw S3RepoError.invalidURL("Endpoint URL must include bucket: \(url)")
            }
            
            let bucket = String(pathComponents[0])
            let prefix = pathComponents.count > 1 ? pathComponents[1...].joined(separator: "/") : ""
            return (bucket, prefix, endpoint)
        } else {
            throw S3RepoError.invalidURL("URL must start with s3://, http://, or https://: \(url)")
        }
    }
    
    private func fullKey(for identifier: String) -> String {
        if prefix.isEmpty {
            return identifier
        } else {
            return "\(prefix)/\(identifier)"
        }
    }
}

/// S3 Repository Plugin Builder
public class S3RepoPluginBuilder: RepoPluginBuilder {
    public override init() {
        super.init()
        logDebug("S3RepoPluginBuilder initialized")
    }
    
    public override func connect(_ url: String) -> Repo? {
        logDebug("S3RepoPluginBuilder.connect() called with URL: \(url)")
        do {
            logDebug("Creating S3Repo instance...")
            let repo = try S3Repo(url)
            logDebug("S3Repo instance created successfully")
            return repo
        } catch {
            logDebug("ERROR in connect(): \(error)")
            print("Failed to connect to S3 repository: \(error)")
            return nil
        }
    }
}

// MARK: - Error Types

enum S3RepoError: LocalizedError {
    case invalidURL(String)
    case noData(String)
    case readError(String)
    case writeError(String)
    
    var errorDescription: String? {
        switch self {
        case .invalidURL(let message):
            return "Invalid URL: \(message)"
        case .noData(let message):
            return "No data: \(message)"
        case .readError(let message):
            return "Read error: \(message)"
        case .writeError(let message):
            return "Write error: \(message)"
        }
    }
}

// MARK: dylib "interface"

/// Function with C calling style for our dylib. We use it to instantiate the Repo object and return an instance
@_cdecl("createPlugin")
public func createPlugin() -> UnsafeMutableRawPointer {
    logDebug("createPlugin() called")
    // Set default region if not already set (for local S3 emulators)
    if ProcessInfo.processInfo.environment["AWS_REGION"] == nil {
        setenv("AWS_REGION", "us-east-1", 0)
        logDebug("AWS_REGION not set, defaulting to us-east-1")
    } else {
        logDebug("AWS_REGION already set: \(ProcessInfo.processInfo.environment["AWS_REGION"] ?? "unknown")")
    }
    logDebug("Creating S3RepoPluginBuilder...")
    let builder = S3RepoPluginBuilder()
    logDebug("Returning plugin builder pointer")
    return Unmanaged.passRetained(builder).toOpaque()
}
