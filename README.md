# Quickwit Helm Chart

## Usage

[Helm](https://helm.sh) must be installed to use the charts. Please refer to
Helm's [documentation](https://helm.sh/docs) to get started.

Once Helm has been set up correctly, add the repo as follows:

    helm repo add quickwit https://helm.quickwit.io

If you had already added this repo earlier, run `helm repo update` to retrieve
the latest versions of the packages. You can then run `helm search repo
quickwit` to see the charts.

To install the quickwit chart:

    helm install my-quickwit quickwit/quickwit

To uninstall the chart:

    helm delete my-quickwit

## Upgrade helm chart from 0.4.0 to 0.5.0

The way storage config is defined changed and you have to update your helm values to upgrade to 0.5.0.

The changes are:
- the `config.s3` and `config.azure_blob` values are no more supported. You now have to use the storage config as defined in the [docs](https://quickwit.io/docs/configuration/storage-config).
- the keys of secrets have changed: `s3.secret_key` is replaced by `storage.s3.secret_access_key` and `azure_blob.access_key` is replace by `storage.azure.access_key`.

## Upgrade helm chart from 0.5.0 to 0.6.0

The way the `config` value works has changed in 0.6.0. It is now copied "as is"
to the Quickwit nodes' configurations. In particular:

- the `config.postgres` section does not support the following attributes
  anymore
```
host: ""
port: 5432
database: metastore
username: quickwit
assword: ""
```
Configure `QW_METASTORE_URI` in `extraEnvFrom` instead (see
[documentation](https://quickwit.io/docs/configuration/metastore-config) for
more details).

- the seed configuration has moved from `config` to a dedicated attribute. The
  changes are:
  - the `config.indexes` field is moved to `seed.indexes`
  - the `config.sources` field is moved to `seed.sources`

## Upgrade helm chart from 0.6.0 to 0.7.0

The `jobs` and `bootstrap` sections got merged in 0.7.0:

* `jobs.sources` section is now replaced by `bootstrap.sources`
* `jobs.indexes` section is now replaced by `bootstrap.indexes`
