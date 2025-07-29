# MLCommons Cloudflare R2 Infra

This repository functions as the source of truth and version control for the metadata and web files that support the [MLC R2 Downloader](https://github.com/mlcommons/r2-downloader). This infrastructure adheres to Infrascuture as Code (IaC) methodology, using GitHub Actions to automatically generate and deploy the infra files based on the dataset information defined in JSON files.

**README Overview:**

* [Infrastructure Components](#infrastructure-components)
    * [Cloudflare R2 Buckets](#cloudflare-r2-buckets)
    * [Cloudflare Access](#cloudflare-access)
        * [Programatic Access](#programatic-access-with-service-tokens)
    * [Metadata Files](#metadata-files)
    * [Download Command Pages](#download-command)
* [Repository Structure](#repository-structure)
* [Defining Bucket Metadata](#defining-bucket-metadata)
* [Generating & Staging Infra Files](#generating--staging-infra-files)
* [Deploying to Prod](#deploying-to-prod)

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

1. A `.uri` file pointing to the directory within a bucket where the files to be downloaded are located. The path to this file is a mandatory arugment for the Downloader.

2. A `.md5` file containing the md5 hashes of each file to be downloaded, as well as the individual paths within the directory specified in the `.uri` file. This file must share the same name as the `.uri` file and be located within the same directory in the bucket as the `.uri` file, as the Downloader automatically fetches the matching `.md5` file based on the provided `.uri` file.

These files should be located within the `metadata` directory at the top of each bucket.

### Download Command Pages

For each bucket configured for use with the MLC R2 Downloader, we provide a webpage with a bit of information about the Downloader, the contents of the bucket, and download commands for the available datasets. These webpages are accesible at the custom domains configured for each bucket. See [inference.mlcommons-storage.org](https://inference.mlcommons-storage.org) for an example.

When visiting the base of a custom domain configured for a R2 bucket, Cloudflare requires that you append a file path within a bucket to the custom domain or else you'll hit a 404 error. To address this issue, we've configured a Redirect Rule to direct traffic from the base of all `mlcommons-storage.org` subdomains to `<subdomain>.mlcommons-storage.org/index.html`. We then place an `index.html` file at the top level of every bucket used in conjuction with the MLC R2 Downloader.

Each of these download command pages follows the same format and shares styling, as well as some content. Thus, rather than duplicating these resources across every bucket, we instead have a central infra bucket (`mlcommons-r2-infra`) to which we deploy a shared CSS stylesheet, Javascript file, HTML file, and set of favicon files. A CORS policy configured in the central infra bucket enables every `index.html` file, when loaded, to pull in the shared styling and content from `r2-infra.mlcommons-storage.org`.

## Repository Structure

Other than the `templates` and `example` directories, every directory in this repo corresponds to a R2 bucket. The `metadata.json` configuration file within each of these directories defines, among other things, the name of the bucket, which the various GitHub Actions workflow in the repo use to determine where to deploy the resources within each bucket.

The `central` directory contains the shared web files that are deployed to the `mlcommons-r2-infra` bucket. The remaining directories correspond to buckets containing data meant for distribution by way of the MLC R2 Downloader. Within each of these directories is an `index.html` file and a `metadata` subdirectory containing `.uri` and `.md5` metadata files. These files are all deployed directly from this repo to the corresponding buckets.

## Defining Bucket Metadata

## Generating & Staging Infra Files

## Deploying to Prod