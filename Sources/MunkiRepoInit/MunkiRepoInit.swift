//
//  S3BucketSetup.swift
//  munki
//
//  Created for S3 bucket repository setup
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

// MARK: - Logger

public struct Logger {
    public enum Level {
        case info
        case warning
        case debug
    }
    
    public var verboseLevel: Int
    
    public init(verboseLevel: Int) {
        self.verboseLevel = verboseLevel
    }
    
    public func log(_ message: String, level: Level = .info) {
        switch level {
        case .info:
            print(message)
        case .warning:
            print("WARNING: \(message)")
        case .debug:
            if verboseLevel >= 2 {
                print("DEBUG: \(message)")
            }
        }
    }
}

// Global logger instance - will be set by main.swift
public var logger = Logger(verboseLevel: 0)

/// Creates and initializes an S3 bucket with the basic munki repository structure
public class MunkiRepoInit {
    private let awsConfig: AWSConfig
    private let s3Client: S3Client
    private let bucketName: String
    
    /// Initialize munki repository setup
    /// - Parameters:
    ///   - bucketName: Name of the S3 bucket to create
    ///   - endpoint: Optional endpoint URL (defaults to AWS_S3_ENDPOINT env var or http://localhost:9001)
    ///   - region: AWS region (defaults to AWS_REGION env var or "us-east-1")
    /// 
    /// Credentials are resolved automatically by the AWS SDK from environment variables, IAM roles, or config files.
    public init(
        bucketName: String,
        endpoint: String? = nil,
        region: String? = nil
    ) async throws {
        self.bucketName = bucketName
        
        // Apply defaults for S3BucketSetup
        let resolvedRegion = region ?? ProcessInfo.processInfo.environment["AWS_REGION"] ?? "us-east-1"
        let resolvedEndpoint = endpoint ?? ProcessInfo.processInfo.environment["AWS_S3_ENDPOINT"] ?? "http://localhost:9001"

        // Initialize AWS configuration
        self.awsConfig = AWSConfig(
            endpoint: resolvedEndpoint,
            region: resolvedRegion
        )
        
        // Create S3 client
        self.s3Client = try await awsConfig.createS3Client()
    }
    
    /// Create bucket and initialize munki repository structure
    /// Creates the following directory structure:
    /// - catalogs/
    /// - manifests/
    /// - pkgs/
    /// - pkgsinfo/
    public func setupRepository() async throws {
        // Create bucket
        try await createBucket()
        
        // Create munki directory structure by uploading empty marker objects
        let directories = ["catalogs", "manifests", "pkgs", "pkgsinfo"]
        for directory in directories {
            try await createDirectory(directory)
        }
    }
    
    /// Create the S3 bucket
    private func createBucket() async throws {
        logger.log("Starting bucket creation for: \(bucketName)", level: .debug)
        logger.log("Region: \(awsConfig.region ?? "not set")", level: .debug)
        
        // Check if bucket already exists
        let headInput = HeadBucketInput(bucket: bucketName)
        do {
            _ = try await s3Client.headBucket(input: headInput)
            // If we get here, the bucket exists
            logger.log("Bucket already exists: \(bucketName)", level: .warning)
            return
        } catch {
            // Bucket doesn't exist, proceed with creation
            logger.log("Bucket does not exist, creating: \(bucketName)", level: .debug)
        }
        
        // For S3-compatible services, include CreateBucketConfiguration with region
        // This sends the proper HTTP request format that rustfs and other S3 implementations expect
        let region = awsConfig.region ?? "us-east-1"
        let createBucketConfig = S3ClientTypes.CreateBucketConfiguration(
            locationConstraint: .init(rawValue: region)
        )
        
        let input = CreateBucketInput(
            bucket: bucketName,
            createBucketConfiguration: createBucketConfig
        )
        do {
            logger.log("Calling s3Client.createBucket...", level: .debug)
            _ = try await s3Client.createBucket(input: input)
            logger.log("Successfully created bucket: \(bucketName)")
        } catch {
            logger.log("Caught error: \(error)", level: .debug)
            throw S3BucketSetupError.bucketCreationFailed("Failed to create bucket: \(error)")
        }
    }
    
    /// Create a directory marker in S3 by uploading an empty object
    private func createDirectory(_ directoryName: String) async throws {
        let key = "\(directoryName)/.keep"
        // Check if directory already exists
        let headInput = HeadObjectInput(bucket: bucketName, key: key)
        do {
            _ = try await s3Client.headObject(input: headInput)
            // If we get here, the object exists
            logger.log("Directory already exists: \(directoryName)", level: .warning)
            return
        } catch {
            // Object doesn't exist, proceed with creation
            logger.log("Directory does not exist, creating: \(directoryName)", level: .debug)
        }
        
        let input = PutObjectInput(
            body: .data(Data()),
            bucket: bucketName,
            key: key
        )
        
        do {
            logger.log("Calling s3Client.putObject for \(key)...", level: .debug)
            _ = try await s3Client.putObject(input: input)
            logger.log("Created directory: \(directoryName)")
        } catch {
            logger.log("Error creating directory \(directoryName): \(error)", level: .debug)
            throw S3BucketSetupError.directoryCreationFailed("Failed to create directory \(directoryName): \(error)")
        }
    }
}

// MARK: - Error Types

public enum S3BucketSetupError: LocalizedError {
    case bucketCreationFailed(String)
    case directoryCreationFailed(String)
    
    public var errorDescription: String? {
        switch self {
        case .bucketCreationFailed(let message):
            return message
        case .directoryCreationFailed(let message):
            return message
        }
    }
}
