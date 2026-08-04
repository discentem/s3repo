# S3Repo

This project provides a [repo plugin](https://github.com/munki/munki/blob/main/code/cli/munki/munkiimport/munkiimport.swift#L190) for Munki 7 to work with an S3 backend.

## Tests

### Automated end-to-end testing

This project includes an automated testing pipeline in Github Actions (see [.github/workflows/end-to-end-repo-plugin-test.yml](.github/workflows/end-to-end-repo-plugin-test.yml)) that handles building, packaging, installing, and testing the plugin with a local S3-compatible server.

This pipeline:
1. Builds the plugin from source
2. Packages it as a .pkg installer
3. Installs it system-wide
5. Starts a rustfs S3-compatible server
6. Creates the munki-repo S3 bucket
7. Runs end-to-end tests with `munkiimport` testing the built S3RepoPlugin.pkg
8. Cleans up all the resources

For more details on individual scripts, see [scripts](scripts/).

## How are repo plugins different than Munki Middleware? 

### Middleware 
[Munki Middleware](https://github.com/munki/munki/wiki/Middleware#munki-7-notes) is installed on Munki _clients_ so that the clients can alter an HTTP(S) request to work with servers (often cloud-based) that require specific headers, keys, or encrypted/signed requests.

### Repo Plugins

Repo plugins allow the Munki command-line admin tools (specifically munkiimport, makecatalogs, iconimporter, manifestutil) to be able to work with a repo that's not just a locally-available filesystem.

