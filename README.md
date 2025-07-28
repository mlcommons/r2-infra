# MLCommons Cloudflare R2 Infra

This repository functions as the source of truth and version control for the metadata and web files that support the [MLC R2 Downloader](https://github.com/mlcommons/r2-downloader). This infrastructure adheres to Infrascuture as Code (IaC) methodology, using GitHub Actions to automatically generate and deploy the infra files based on the dataset information defined in JSON files.

**README Overview:**

* [Infrastructure Components](Infrastructure-Components)
    * [Cloudflare R2 Buckets](Infrastructure-Components#cloudflare-r2-buckets)
    * [Cloudflare Access](Infrastructure-Components#cloudflare-access)
        * [Programatic Access](Infrastructure-Components#programatic-access-with-service-tokens)
    * [Metadata Files](Infrastructure-Components#metadata-files)
    * [Download Command Pages](Infrastructure-Components#download-command-pages-indexhtml)
* [Defining Metadata](Defining-Metadata)
* [Generating & Staging Infra Files](Generating-&-Staging-Infra-Files)
* [Deploying to Prod](Deploying-to-Prod)

## Infrastructure Components

### Cloudflare R2 Buckets

Buckets containing data to be distributed via the MLC R2 Downloader require a custom domain to be configured in the bucket's settings. This custom domain should be a subdomain of `mlcommons-storage.org`, which is domain registered with Cloudflare specifically for R2 data distribution. When configuring the custom domain in the bucket, set the minimum TLS version to 1.2, as version 1.0 and 1.1 are legacy versions with significant security vunerabilities.

### Cloudflare Access

In the case of a bucket used to distribute data with an authentication requirement, such as Members-only access and or a license agreement, a Cloudflare Access Application must be created for the bucket subdomain _**before**_ configuring the subdomain in the bucket settings. Configuration in the reverse order would result in a period in which unauthorized unauthorized access would be possible.

Cloudflare Access Application requirements:

* A dedicated Access Policy with a session length of two weeks that allows anyone in a dedicated Rule Group to access the application.
* Login methods of One-time PIN and Google SSO
* A custom application logo with the following URL: `https://assets.mlcommons-storage.org/logos/mlcommons/mlc_logo_black_green.png`

#### Programatic Access with Service Tokens

The MLC R2 Downloader supports service tokens defined as environment variables using the `-s` flag. If programmatic access to the bucket is needed, you can add a Service Auth Access Policy to the Access Application to allow defined service tokens to access the application.

### Metadata Files

In order to download a dataset, the MLC R2 Downloader needs two metadata files:

1. A .uri file pointing to the directory within a bucket where the files to be downloaded are located. The path to this file is a mandatory arugment for the Downloader.

2. A .md5 file containing the md5 hashes of each file to be downloaded, as well as the individual paths within the directory specified in the .uri file. This file must share the same name as the .uri file and be located within the same directory in the bucket as the .uri file, as the Downloader automatically fetches the matching .md5 file based on the provided .uri file.

These files should be located within the `metadata` directory at the top of each bucket.

### Download Command Pages (index.html)

## Defining Metadata (metadata.json)

## Generating & Staging Infra Files

## Deploying to Prod