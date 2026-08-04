# S3Repo

This project provides a [repo plugin](https://github.com/munki/munki/blob/main/code/cli/munki/munkiimport/munkiimport.swift#L190) for Munki 7 that uses the S3 API to 'talk' to the repo.

## How to test this repo plugin

### Automated end-to-end testing

This project includes an automated testing pipeline that handles building, packaging, installing, and testing the plugin with a local S3-compatible server.

This wrapper script:
1. Builds the plugin from source
2. Packages it as a .pkg installer
3. Installs it system-wide
4. Builds the MunkiRepoInit tool
5. Starts a rustfs S3-compatible server
6. Creates the munki-repo S3 bucket
7. Runs end-to-end tests with `munkiimport` testing the built S3RepoPlugin.pkg
8. Cleans up resources

For more details on individual scripts, see [scripts](scripts/).

## How are repo plugins different than Munki Middleware? 

### Middleware 
[Munki Middleware](https://github.com/munki/munki/wiki/Middleware#munki-7-notes) is installed on Munki _clients_ so that the clients can alter an HTTP(S) request to work with servers (often cloud-based) that require specific headers, keys, or encrypted/signed requests.

### Repo Plugins

Repo plugins are used by Munkitools, such as [Munkiimport](https://github.com/munki/munki/blob/main/code/cli/munki/munkiimport/munkiimport.swift#L190), when an administrator is interacting with the Munki repo. 

