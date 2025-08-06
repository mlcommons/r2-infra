# MLCommons Cloudflare R2 Infra

This repository functions as the source of truth and version control for the metadata and web files that support the [MLC R2 Downloader](https://github.com/mlcommons/r2-downloader). This infrastructure adheres to Infrastructure as Code (IaC) methodology, using GitHub Actions to automatically generate and deploy the infra files based on bucket information defined in JSON manifest files.

**README Table of Contents:**

* [Infrastructure Components](#infrastructure-components)
    * [Cloudflare R2 Buckets](#cloudflare-r2-buckets)
        * [R2 API Token](#r2-api-token)
    * [Cloudflare Access](#cloudflare-access)
        * [Programatic Access](#programatic-access-with-service-tokens)
    * [Metadata Files](#metadata-files)
    * [Download Command Pages](#download-command)
* [Repository Structure](#repository-structure)
* [Defining Bucket Manifests](#defining-bucket-manifests)
    * [Specifying Destination Directory](#specifying-destination-directory)
    * [Overriding File Generation](#overriding-file-generation)
    * [Updating Metadata](#updating-metadata)
    * [Deleting Metadata](#deleting-metadata)
* [Generating & Staging Infra Files](#generating--staging-infra-files)
    * [Automated File Generation](#automated-file-generation)
    * [Staging Environment](#staging-environment)
    * [Staging Review Process](#staging-review-process)
    * [Manual Metadata Generation](#manual-metadata-generation)
* [Deploying to Prod](#deploying-to-prod)
    * [Production Deployment Workflows](#production-deployment-workflows)
    * [Deployment Process](#deployment-process)
    * [Manual Deployment](#manual-deployment)
    * [Post-Deployment Verification](#post-deployment-verification)
    * [Deployment Architecture](#deployment-architecture)

## Infrastructure Components

### Cloudflare R2 Buckets

Buckets containing data to be distributed via the MLC R2 Downloader require a custom domain to be configured in the bucket's settings. This custom domain should be a subdomain of `mlcommons-storage.org`, which is domain registered with Cloudflare specifically for R2 data distribution. When configuring the custom domain in the bucket, set the minimum TLS version to 1.2, as version 1.0 and 1.1 are legacy versions with significant security vunerabilities.

#### R2 API Token

This repo uses the `r2-deploy` R2  Account API Token to access all the buckets used with the MLC R2 Downloader. **If you add a bucket manifest (see [Defining Bucket Manifests](#defining-bucket-manifests)) to this repo, you will need to grant this API token access to the corresponding bucket.**

This token is stored in 1Password and the GitHub Actions workflows in this repo use the [`1password/load-secrets-action`](https://github.com/marketplace/actions/load-secrets-from-1password) action to fetch the credentials.

### Cloudflare Access

In the case of a bucket used to distribute data with an authentication requirement, such as Members-only access and or a license agreement, a Cloudflare Access Application must be created for the bucket subdomain _**before**_ configuring the subdomain in the bucket settings. Configuration in the reverse order would result in a period in which unauthorized access would be possible.

Clouflare Access is usually used in conjunction with the [License Agreement Flow](https://github.com/mlcommons/license-agreement-flow) system, which automatically adds users to a Cloudflare Access Rule Group once they've signed a EULA, granting them access to the corresponding bucket.

**Cloudflare Access Application requirements:**

* A dedicated Access Policy with a session length of two weeks that allows anyone in a dedicated Rule Group to access the application.
* Login methods of One-time PIN and Google SSO
* A custom application logo with the following URL: `https://assets.mlcommons-storage.org/logos/mlcommons/mlc_logo_black_green.png`
* A custom access error directing people to the EULA page, if applicable.

#### Programatic Access with Service Tokens

The MLC R2 Downloader supports service tokens defined as environment variables using the `-s` flag. If programmatic access to the bucket is needed, you can add a Service Auth Access Policy to the Access Application to allow defined service tokens to access the application.

### Metadata Files

In order to download a dataset, the MLC R2 Downloader needs two metadata files:

1. A `.uri` file pointing to the directory within a bucket where the files to be downloaded are located. The path to this file is a mandatory arugment for the Downloader.

2. A `.md5` file containing the md5 hashes of each file to be downloaded, as well as the individual paths within the directory specified in the `.uri` file. This file must share the same name as the `.uri` file and be located within the same directory in the bucket as the `.uri` file, as the Downloader automatically fetches the matching `.md5` file based on the provided `.uri` file.

These files should be located within the `metadata` directory at the top of each bucket.

**If the files within a dataset are changed, the `.md5` file for said dataset will need to be updated (see [Updating Metadata](#updating-metadata)).**

### Download Command Pages

For each bucket configured for use with the MLC R2 Downloader, we provide a webpage with a bit of information about the Downloader, the contents of the bucket, and download commands for the available datasets. These webpages are accesible at the custom domains configured for each bucket. See [inference.mlcommons-storage.org](https://inference.mlcommons-storage.org) for an example.

When visiting the base of a custom domain configured for a R2 bucket, Cloudflare requires that you append a file path within a bucket to the custom domain or else you'll hit a 404 error. To address this issue, we've configured a Redirect Rule to direct traffic from the base of all `mlcommons-storage.org` subdomains to `<subdomain>.mlcommons-storage.org/index.html`. We then place an `index.html` file at the top level of every bucket used in conjuction with the MLC R2 Downloader.

Each of these download command pages follows the same format and shares styling, as well as some content. Thus, rather than duplicating these resources across every bucket, we instead have a central infra bucket (`mlcommons-r2-infra`) to which we deploy a shared CSS stylesheet, Javascript file, HTML file, and set of favicon files. A CORS policy configured in the central infra bucket enables every `index.html` file, when loaded, to pull in the shared styling and content from `r2-infra.mlcommons-storage.org`.

## Repository Structure

Other than the `templates` and `example` directories, every directory in this repo corresponds to a R2 bucket. The `manifest.json` configuration file within each of these directories defines, among other things, the name of the bucket, which the various GitHub Actions workflow in the repo use to determine where to deploy the resources within each bucket.

The `central` directory contains the shared web files that are deployed to the `mlcommons-r2-infra` bucket. The remaining directories correspond to buckets containing data meant for distribution by way of the MLC R2 Downloader. Within each of these directories is an `index.html` file and a `metadata` subdirectory containing `.uri` and `.md5` files. These files are all deployed directly from this repo to the corresponding buckets (see [Deploying to Prod](#deploying-to-prod)).

## Defining Bucket Manifests

Every directory in this repo that corresponds to a R2 bucket contains a `manifest.json` file that defines the bucket name and URL, as well as the datasets within it and their descriptive information. As described below, GitHub Actions workflows in this repo automatically generate and deploy the `index.html` file and metadata (`.uri` & `.md5`) files associated with each bucket according to the information defined in its manifest. Unless you need to customize these files beyond what is possible using the manifest properties, you shouldn't touch them directly. _If a modification is more than a one-off, consider submitting a PR to add a manifest property._

**The metadata and web file generation workflows run automatically when a PR targeting main is opened or updated and the PR contains changes to `manifest.json` files.**

The [`example-manifest.jsonc`](example/example-manifest.jsonc) file in the example directory serves as a commented example of a manifest, with the comments explaining each property. Bucket manifests use the following heirarchical structure:

```
{
  bucket info
  datasets {
    category [
      {
        dataset info
      }
    ]
  }
}
```

### Specifying Destination Directory

By default, the MLC R2 Downloader determines the destination directory based on the contents of the metadata files. If the `.md5` file specifies only a single file to be downloaded, the Downloader downloads the files directly to the current working directory from which the script was run. If more than one file is specified, then the Downloader downloads the files into a directory with the same name as the directory containing the files in the bucket.

In some cases you may want to specify an alternative download directory, and the Downloader supports doing so with the `-d <download-path>` option. While anyone can modify the destination directory by passing this flag with the download command, you can define a destination directory to be included in the official download command for each dataset displayed on the download command web pages. You can do so by adding the `destination` property to a dataset defined in a bucket manifest. Then, when the `index.html` files are generated, a matching `-d` flag will be added to the appropriate download command.

With the `destination` property you can define the download destination as the working directory (`./`), a single directory (`<directory-name>`), or even a file path with multiple directories (`<directory-name>/<subdirectory-name>`).

### Overriding File Generation

In the case that you do need to make a modification to a file generated by the GitHub Actions workflows, there are two properties you can include to prevent the workflows from writing over your changes:

* `"index_override": true` - set at the top level of the manifest to override `index.html` generation
* `"metadata_override": true` - set at the individual dataset level to override metadata file generation for that dataset

### Updating Metadata

If the files within a dataset are changed, the `.md5` file for said dataset will need to be updated. You can force such an update by adding an empty new line at the bottom of the corresponding bucket manifest and opening a PR targeting main to trigger the metadata generation workflow.

### Deleting Metadata

Metadata files corresponding to datasets that were previously defined in a bucket manifest but have since been removed will not be automatically removed from the repo or the bucket. These files will continue to live on to support an legacy downloads that may still be in use. If you need to fully deprecate a download, you will need to manually remove the supporting metadata files from both the repo and bucket metadata directories.

## Generating & Staging Infra Files

When you submit a pull request that modifies bucket manifests or web content, GitHub Actions workflows automatically generate the necessary infrastructure files and deploy them to a staging environment for testing and review.

### Automated File Generation

The repository uses several automated workflows to generate infrastructure files:

#### 1. Web Page Generation

When you modify a `manifest.json` file, the [`deploy-r2-staging.yml`](.github/workflows/deploy-r2-staging.yml) workflow uses the [`generate-web-pages.sh`](.github/scripts/generate-web-pages.sh) script to automatically:

- Generates `index.html` files from the [`template-index.html`](templates/template-index.html) template
- Populates dataset sections based on the manifest configuration
- Handles expandable sections if `index_expandable` is set to `true`
- Commits the generated files back to your PR branch

#### 2. Metadata File Generation

The [`gen-metadata.yml`](.github/workflows/gen-metadata.yml) workflow automatically:

- Connects to the corresponding R2 buckets using Rclone
- Generates `.uri` files containing the dataset access URLs
- Generates `.md5` files with checksums for all files in each dataset
- Calculates and adds dataset sizes to the manifest files
- Commits the generated metadata files back to your PR branch
- Uploads staging versions of metadata files with `staging-<PR#>-` prefixes

### Staging Environment

Pull requests automatically deploy to a staging environment at `https://r2-infra-staging.mlcommons-storage.org/<PR#>/` where:

- **Web files**: Modified `index.html` files are deployed with rewritten URLs pointing to staging resources
- **Central assets**: Shared CSS, JS, and content files are deployed under the PR-specific path
- **Metadata files**: Staged with `staging-<PR#>-` prefixes in production buckets for testing

### Staging Review Process

Each PR receives automated comments with:

- **Web staging URLs**: Direct links to test each dataset's download page
- **Metadata summary**: List of generated/modified metadata files
- **Dataset sizes**: Automatically calculated file counts and sizes
- **Changed files**: Comparison against the main branch

You can verify your changes by:

1. Visiting the staging URLs provided in the PR comment
2. Testing download commands with the staged metadata files
3. Confirming that dataset information displays correctly
4. Confirming the changed files include only files you intended to add/modify (_if a random `.md5` file unexpectedly changed, it's possible files within the bucket were recently updated and the associated hashsums have not yet been updated_)

### Manual Metadata Generation

For local development or troubleshooting, you can use the [`generate-r2-metadata.sh`](generate-r2-metadata.sh) script:

```bash
# Interactive metadata generation
bash generate-r2-metadata.sh

# The script will prompt for:
# - Bucket name and path
# - Public URL for the bucket
# - Dataset name
# - R2 credentials
```

This script generates the same `.uri` and `.md5` files that the automated workflow creates, useful for testing locally or generating metadata for new datasets before committing manifest changes.

## Deploying to Prod

Production deployment occurs automatically when pull requests are merged into the `main` branch. The process involves two separate workflows that deploy different types of content to their respective R2 buckets.

### Production Deployment Workflows

#### 1. Web Files Deployment

The [`deploy-r2.yml`](.github/workflows/deploy-r2.yml) workflow triggers on pushes to `main` and:

- **Central resources**: Deploys shared CSS, JS, and content files to the `mlcommons-r2-infra` bucket
- **Dataset pages**: Deploys `index.html` files to their respective dataset buckets

#### 2. Metadata Files Deployment

The [`deploy-metadata.yml`](.github/workflows/deploy-metadata.yml) workflow triggers on changes to metadata files and:

- **URI files**: Deploys `.uri` files containing dataset access URLs
- **Checksum files**: Deploys `.md5` files with file checksums
- **Content headers**: Sets appropriate `Content-Type: text/plain; charset=utf-8` headers for the metadata files

### Deployment Process

1. **Merge to main**: When a PR is merged, both workflows trigger automatically
2. **Credential loading**: Workflows securely load R2 credentials from 1Password
3. **Rclone configuration**: Sets up authenticated connections to Cloudflare R2
4. **File deployment**: 
   - Web files go to their target buckets (e.g., `mlcommons-inference` → `inference.mlcommons-storage.org`)
   - Metadata files are placed in `/metadata/` directories within each bucket
5. **Verification**: Workflows report deployment status and file counts

### Manual Deployment

Production deployments can also be triggered manually:

- **Web files**: Use the "Run workflow" button on the [`deploy-r2.yml`](.github/workflows/deploy-r2.yml) workflow
- **Metadata files**: Use the "Run workflow" button on the [`deploy-metadata.yml`](.github/workflows/deploy-metadata.yml) workflow

### Post-Deployment Verification

After deployment, verify that:

1. **Download pages** are accessible at their custom domains (e.g., `https://inference.mlcommons-storage.org`)
2. **Download commands** work correctly with the deployed metadata files
3. **Shared resources** load properly from the central infrastructure bucket

### Deployment Architecture

The deployment follows this structure:

```
Production Buckets:
├── mlcommons-r2-infra/           # Central shared resources
│   └── central/                  # CSS, JS, content, favicons
├── mlcommons-inference/          # Inference datasets
│   ├── index.html               # Dataset download page
│   └── metadata/                # .uri and .md5 files
├── mlcommons-training/           # Training datasets
│   ├── index.html
│   └── metadata/
└── [other dataset buckets...]

Custom Domains:
├── r2-infra.mlcommons-storage.org     → mlcommons-r2-infra
├── inference.mlcommons-storage.org    → mlcommons-inference  
├── training.mlcommons-storage.org     → mlcommons-training
└── [other domains...]
```

This architecture ensures that each dataset bucket is self-contained while sharing common resources efficiently through CORS-enabled cross-bucket loading.
