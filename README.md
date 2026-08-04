# S3Repo

This project provides a [repo plugin](https://github.com/munki/munki/blob/main/code/cli/munki/munkiimport/munkiimport.swift#L190) for Munki 7 that uses the S3 API to 'talk' to the repo.

## How to test this repo plugin

### Automated end-to-end testing

This project includes an automated testing pipeline that handles building, packaging, installing, and testing the plugin with a local S3-compatible server.

Run the full test suite:

```shell
sh scripts/run-full-test.sh
```

This wrapper script:
1. Builds the plugin from source
2. Packages it as a .pkg installer
3. Installs it system-wide
4. Builds the MunkiRepoInit tool
5. Starts a rustfs S3-compatible server
6. Creates the munki-repo S3 bucket
7. Runs end-to-end tests with `munkiimport` testing the built S3RepoPlugin.pkg
8. Cleans up resources

For more details on individual scripts, see below.

### Testing individual components

**Build S3Repo plugin package:**
```shell
sh scripts/build-plugin-package.sh
```

**Build MunkiRepoInit tool (required for bucket creation):**
```shell
sh scripts/build-munki-repo-init.sh
```

**Start rustfs server:**
```shell
# Start server with default settings
RUSTFS_PID=$(sh scripts/start-rustfs.sh)

# With custom settings
RUSTFS_PID=$(sh scripts/start-rustfs.sh --dir /tmp/s3 --port 9000)

# Clean up
kill $RUSTFS_PID
```

**Create S3 bucket:**
```shell
# Create bucket with defaults
sh scripts/create-s3-bucket.sh

# With custom settings
sh scripts/create-s3-bucket.sh --bucket my-repo --endpoint http://localhost:9000
```

**Run munkiimport test:**
```shell
# Test the built S3RepoPlugin.pkg (default)
sh scripts/test_munkiimport.sh

# With custom application/package
sh scripts/test_munkiimport.sh --app /path/to/test-app.dmg

# With custom repo URL
sh scripts/test_munkiimport.sh --repo-url http://localhost:9000/my-repo
```

### GitHub Actions CI/CD

This project includes a GitHub Actions workflow that runs automated tests on push and pull requests. The workflow runs on macOS and includes the following stages:

- Install munkitools
- Install rustfs
- Build S3Repo plugin package
- Build MunkiRepoInit tool
- Install S3Repo plugin package
- Start rustfs S3 server
- Create S3 bucket
- Run munkiimport end-to-end test (tests S3RepoPlugin.pkg)
- Cleanup

See [.github/workflows/test.yml](.github/workflows/test.yml) for the full workflow definition.

## How are repo plugins different than Munki Middleware? 

### Middleware 
[Munki Middleware](https://github.com/munki/munki/wiki/Middleware#munki-7-notes) is installed on Munki _clients_ so that the clients can alter an HTTP(S) request to work with servers (often cloud-based) that require specific headers, keys, or encrypted/signed requests.

### Repo Plugins

Repo plugins are used by Munkitools, such as [Munkiimport](https://github.com/munki/munki/blob/main/code/cli/munki/munkiimport/munkiimport.swift#L190), when an administrator is interacting with the Munki repo. 

