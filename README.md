# S3Repo

This project provides a [repo plugin](https://github.com/munki/munki/blob/main/code/cli/munki/munkiimport/munkiimport.swift#L190) for Munki 7 that uses the S3 API to 'talk' to the repo.

## How to test this repo plugin

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

