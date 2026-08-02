//
//  AWSConfig.swift
//  munki
//
//  Created for AWS configuration utilities
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

/// AWS configuration (optional overrides - SDK uses credential chain by default)
public struct AWSConfig {
    public let endpoint: String?
    public let region: String?
    
    /// Initialize AWS configuration
    /// - Parameters:
    ///   - endpoint: Optional endpoint URL (defaults to AWS_S3_ENDPOINT env var)
    ///   - region: Optional AWS region (defaults to AWS_REGION env var)
    /// 
    /// Credentials are resolved automatically by the AWS SDK from:
    /// - Environment variables (AWS_ACCESS_KEY_ID, AWS_SECRET_ACCESS_KEY, AWS_SESSION_TOKEN)
    /// - IAM instance profile (EC2)
    /// - ECS container credentials
    /// - ~/.aws/credentials file
    /// - ~/.aws/config file
    public init(
        endpoint: String? = nil,
        region: String? = nil
    ) {
        self.endpoint = endpoint ?? ProcessInfo.processInfo.environment["AWS_S3_ENDPOINT"]
        self.region = region ?? ProcessInfo.processInfo.environment["AWS_REGION"]
    }
    
    /// Create an S3Client configured with this AWS configuration
    public func createS3Client() async throws -> S3Client {
        var config = try await S3Client.S3ClientConfig()
        
        if let endpoint = endpoint {
            config.endpoint = endpoint
            
            // Force path-style URLs for http and https endpoints (e.g., local S3-compatible services like rustfs, MinIO)
            // AWS CLI also sets ForcePathStyle: True for http:// endpoints
            // This prevents the SDK from using virtual-hosted-style URLs (bucket.localhost) 
            // which don't work with local endpoints
            if endpoint.lowercased().starts(with: "http://") || endpoint.lowercased().starts(with: "https://") {
                config.forcePathStyle = true
            }
        }
        
        if let region = region {
            config.region = region
        }
        
        return S3Client(config: config)
    }
}
