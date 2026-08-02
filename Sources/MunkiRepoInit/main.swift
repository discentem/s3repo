//
//  main.swift
//  S3BucketSetup
//
//  Entry point for S3BucketSetup CLI tool
//

import Foundation
import ArgumentParser
import MunkiRepoInit

@main
struct BucketSetupCLI: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "S3BucketSetup",
        abstract: "Creates and initializes an S3 bucket with munki repository structure",
        discussion: "Sets up the basic directory structure needed for a munki repository in S3.",
        version: "1.0.0"
    )
    
    @Argument(help: "Name of the S3 bucket to create")
    var bucketName: String
    
    @Option(name: .long, help: "S3 endpoint URL")
    var endpoint: String = "http://localhost:9000"
    
    @Option(name: .long, help: "AWS region")
    var region: String = "us-east-1"
    
    @Flag(name: .shortAndLong, help: "Enable debug logging")
    var verbose: Bool = false
    
    mutating func run() async throws {
        // Set the logger with the verbosity level (1 if verbose flag is set, 0 otherwise)
        logger = Logger(verboseLevel: verbose ? 2 : 0)
        
        logger.log("Setting up S3 bucket: \(bucketName)")
        logger.log("Endpoint: \(endpoint)")
        logger.log("Region: \(region)")
        
        logger.log("Creating MunkiRepoInit instance...", level: .debug)
        let setup = try await MunkiRepoInit(bucketName: bucketName, endpoint: endpoint, region: region)
        logger.log("MunkiRepoInit instance created", level: .debug)
        
        logger.log("Calling setupRepository...", level: .debug)
        try await setup.setupRepository()
        logger.log("setupRepository completed", level: .debug)
        
        logger.log("Successfully initialized repository structure in \(bucketName)")
    }
}
