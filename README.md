# S3Repo

This project provides a [repo plugin](https://github.com/munki/munki/blob/main/code/cli/munki/munkiimport/munkiimport.swift#L190) for Munki 7 that uses the S3 API to 'talk' to the repo.

## How to test this repo plugin

### Automated end-to-end testing

This project includes an automated testing pipeline that handles building, packaging, installing, and testing the plugin with a local S3-compatible server.

Run the full test suite:

```shell
# Keep rustfs running after tests (useful for debugging)
sh scripts/run-full-test.sh true /path/to/test-app.dmg

# Or without keeping rustfs alive
sh scripts/run-full-test.sh false /path/to/test-app.dmg
```

This wrapper script:
1. Builds the plugin from source
2. Packages it as a .pkg installer
3. Installs it system-wide
4. Runs end-to-end tests with `munkiimport` using a local rustfs S3-compatible server
5. Cleans up resources (unless you specify to keep rustfs alive)

For more details, see:
- [`scripts/run-full-test.sh`](scripts/run-full-test.sh) - Main test orchestrator
- [`scripts/test_munkiimport.sh`](scripts/test_munkiimport.sh) - Individual test runner with timeout and logging
- [`scripts/build-plugin-package.sh`](scripts/build-plugin-package.sh) - Plugin build and packaging
- [`scripts/install-plugin-package.sh`](scripts/install-plugin-package.sh) - Plugin installation

### Manual testing

For manual testing without the automated wrapper:

1. Either create a real S3 bucket or run a S3-compatible service and create a bucket there. Note down the access key and secret key that you set.

    For example, with Rustfs:

    ```shell
    rustfs server ~/rustfs-buckets --console-enable --access-key="blah" --secret-key="blah"
    ```

1. Create a Munki repo. For convenience this project provides a command-line tool that can set up a basic Munki repository for you. 

    If you are using rustfs or a similiar S3-compatible service:

    ```
    AWS_ACCESS_KEY_ID="blah" && AWS_SECRET_ACCESS_KEY="blah" && swift run MunkiRepoInit --endpoint http://localhost:9000 munki-repo
    ```

    If you are using real s3:

    ```
    AWS_ACCESS_KEY_ID="blah" AWS_SECRET_ACCESS_KEY="blah" swift run MunkiRepoInit munki-repo
    ```
1. Download a package that you want to import into Munki, such as [Ghostty](https://release.files.ghostty.org/1.3.1/Ghostty.dmg).

1. Install the [latest Munkitools](https://github.com/munki/munki/releases/).

## How are repo plugins different than Munki Middleware? 

### Middleware 
[Munki Middleware](https://github.com/munki/munki/wiki/Middleware#munki-7-notes) is installed on Munki _clients_ so that the clients can alter an HTTP(S) request to work with servers (often cloud-based) that require specific headers, keys, or encrypted/signed requests.

### Repo Plugins

Repo plugins are used by Munkitools, such as [Munkiimport](https://github.com/munki/munki/blob/main/code/cli/munki/munkiimport/munkiimport.swift#L190), when an administrator is interacting with the Munki repo. 

