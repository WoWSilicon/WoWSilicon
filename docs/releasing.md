# Releasing

WoWSilicon releases are created from version tags such as `v2.6.0`.

## GitHub Setup

The `WoWSilicon/WoWSilicon` repository needs these Actions secrets:

- `SPARKLE_PRIVATE_KEY`
- `PAGES_REPO_TOKEN`

`PAGES_REPO_TOKEN` must have contents write access to `WoWSilicon/wowsilicon.github.io`.

## Versioning

The app uses semantic versions for display and a numeric build number for update ordering.

```text
2.5.0  -> 20500
2.5.1  -> 20501
2.5.10 -> 20510
2.6.0  -> 20600
```

The release workflow computes the build number automatically from the tag.

## Local Builds

```sh
make bundle
make dmg
make appcast
```

For a specific version:

```sh
make dmg VERSION=2.6.0 BUILD_NUMBER=20600
```

## Release Flow

Update the version, commit it, then create and push a tag:

```sh
tools/release/set_version.sh 2.6.0
git add Packaging/Info.plist Project.swift
git commit -m "Bump version to 2.6.0"
git tag v2.6.0
git push origin main --tags
```

The GitHub Action builds the DMG, creates or updates the GitHub Release, generates the signed update feed, and publishes `appcast.xml` to the Pages repository.
