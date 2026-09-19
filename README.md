# terraform-confluent-cloud

Terraform for Confluent Cloud topic management: it looks up an existing environment and
Kafka cluster, creates a dedicated service account with a role binding and its own Kafka
API key, and manages the topic inventory as data. The part worth looking at is how the
topics are declared. A configuration like this usually grows one hand-written
`confluent_kafka_topic` block per topic, each restating the same dozen settings, until a
retention change means editing eighteen near-identical blocks and hoping none was missed.
Here the inventory is a map, the behaviour is a single resource with `for_each`, and the
shared settings live in two named presets. Adding a topic is one line; changing a setting
for every topic is one edit.

## Architecture

```
  variables.tf ─ environment, cluster_name, domain, retention, partitions
  locals.tf    ─ two config presets + three topic maps
        │
        v
 ┌─────────────────────────── root module ────────────────────────────┐
 │                                                                    │
 │  data.confluent_environment.this      (looked up, not created)     │
 │  data.confluent_kafka_cluster.this    (looked up, not created)     │
 │            │                                                       │
 │            v                                                       │
 │  confluent_service_account.topic_manager                           │
 │  confluent_role_binding.topic_manager    ── CloudClusterAdmin      │
 │  confluent_api_key.topic_manager         ── created by Terraform   │
 │            │                                                       │
 │            ├──────────────┬───────────────┬──────────────────      │
 │            v              v               v                        │
 │   module "cdc_topics"  module        module "stream_topics"        │
 │                       "producer_topics"                            │
 │   prefix:             prefix:         prefix:                      │
 │   <domain>.<env>.cdc. ...events.      ...streams.                  │
 │   preset: compacted   preset:         preset: retained             │
 │   18 topics           retained        1 topic                      │
 │                       3 topics                                     │
 └────────────────────────────────────────────────────────────────────┘
                              │
                              v
            ┌───────────────────────────────────────┐
            │      modules/topics                   │
            │                                       │
            │  resource "confluent_kafka_topic" {   │
            │    for_each = var.topics              │
            │    config   = merge(default, own)     │
            │  }                                    │
            │                                       │
            │  one block, any number of topics      │
            └───────────────────────────────────────┘
                              │
                              v
                      Confluent Cloud
                  (topics created over the
                   cluster REST endpoint)
```

## The refactor this repository is about

The configuration this is derived from had, in one file, eighteen blocks of this shape:

```hcl
resource "confluent_kafka_topic" "orders" {
  kafka_cluster { id = var.kafka_cluster_id }
  topic_name       = "${var.topic_prefix}-orders"
  partitions_count = 1
  rest_endpoint    = var.cluster_http_endpoint
  config = {
    "cleanup.policy"                      = "compact"
    "max.message.bytes"                   = "2097164"
    "retention.ms"                        = "1209600000"
    "retention.bytes"                     = "-1"
    "delete.retention.ms"                 = "86400000"
    "max.compaction.lag.ms"               = "9223372036854775807"
    "message.timestamp.difference.max.ms" = "9223372036854775807"
    "message.timestamp.type"              = "CreateTime"
    "min.compaction.lag.ms"               = "0"
    "min.insync.replicas"                 = "2"
    "segment.bytes"                       = "104857600"
    "segment.ms"                          = "604800000"
  }
  credentials { key = var.api_key, secret = var.api_secret }
}

resource "confluent_kafka_topic" "order_lines" {
  # ... the same 25 lines again, with a different topic_name
}
# ... sixteen more
```

495 lines in which the only meaningful variation was `topic_name`. It worked, and it is a
maintenance trap: every shared setting existed in eighteen places, so changing the
retention policy was eighteen identical edits and any block missed drifted silently, with
nothing in the plan pointing at the inconsistency.

The replacement is one resource and one map:

```hcl
# locals.tf: the settings, declared once
compacted_config = merge(local.common_config, {
  "cleanup.policy"      = "compact"
  "retention.ms"        = var.cdc_retention_ms
  "delete.retention.ms" = "86400000"
})

# locals.tf: the inventory, as data
cdc_topics = {
  "orders"      = {}
  "order_lines" = {}
  "change_log"  = { config = { "cleanup.policy" = "delete" } }
  # ...
}

# modules/topics/main.tf: the behaviour, once
resource "confluent_kafka_topic" "this" {
  for_each         = var.topics
  topic_name       = "${var.topic_prefix}${each.key}"
  partitions_count = coalesce(each.value.partitions_count, var.default_partitions_count)
  config           = merge(var.default_config, each.value.config)
  # ...
}
```

What that buys, concretely:

- **A shared change is one edit.** Retention moves for all eighteen CDC topics by changing
  one variable, and the plan shows eighteen in-place updates, so the blast radius is
  visible before apply.
- **Drift becomes impossible by construction.** Two topics cannot disagree on
  `min.insync.replicas` unless someone deliberately overrode it, and the override is one
  visible line.
- **Adding a topic is one line** instead of copying 25 and editing one of them.
- **The intent is legible.** `compacted_config` and `retained_config` name the two shapes
  that actually exist, instead of leaving a reader to diff two blocks to find out whether
  they differ on purpose.
- **Exceptions stay obvious.** `change_log` overriding `cleanup.policy` is one line in a
  map, not a difference buried in the twelfth line of the fourteenth block.

The cost, which is real: the map key becomes the resource identity in state. Renaming a
key is a destroy and recreate unless you `terraform state mv` first. That is documented in
[`modules/topics/README.md`](modules/topics/README.md) along with the other sharp edges.

## Features

- Topic inventory as data, with shared defaults and per-topic overrides merged over them.
- Two named configuration presets, compacted for CDC latest-state topics and retained for
  append-only event topics, each explaining why its settings are what they are.
- Environment and cluster looked up rather than created, so topic changes cannot destroy a
  cluster.
- The Kafka API key is created by Terraform and owned by a Terraform-managed service
  account, so the only credential supplied from outside is the Confluent Cloud API key.
- Environment-parameterised: one configuration serves dev and production through
  `-var environment=...`, with the environment in the topic prefix.
- Input validation on the environment name, the domain, partition counts, topic names and
  the role name, so a typo fails at plan time.
- Partial S3 backend configuration with no credentials in the Terraform files.
- CI that checks formatting, validates the root module, the child module and both
  examples, runs TFLint and a Trivy IaC scan, and fails the build if state, a plan file, a
  `tfvars` file or a credential-shaped string is ever committed.
- Two runnable examples: the module on its own, and the full root configuration.

## Prerequisites

- Terraform 1.5 or newer.
- A Confluent Cloud organisation with an existing environment and an existing Kafka
  cluster. This configuration manages topics, not clusters.
- A Confluent Cloud API key for a service account with permission to create service
  accounts, role bindings and API keys in that environment. `EnvironmentAdmin` is
  sufficient; `OrganizationAdmin` is more than needed.
- For remote state, an S3 bucket and credentials to reach it, ideally through an assumed
  role rather than static keys.

## Configuration

| Variable | Description | Default |
|---|---|---|
| `environment` | Display name of the target Confluent Cloud environment. Also interpolated into topic prefixes. | required |
| `cluster_name` | Display name of the existing Kafka cluster. | required |
| `confluent_cloud_api_key` | Cloud API key Terraform authenticates with. Sensitive. | required |
| `confluent_cloud_api_secret` | Cloud API secret. Sensitive. | required |
| `domain` | Logical domain prefixing every topic name, so teams can share a cluster. | `sales` |
| `service_account_name` | Display name of the managed service account. Must be unique across the organisation. | `terraform-<domain>-<environment>` |
| `cluster_role` | Role bound to the service account. One of `CloudClusterAdmin`, `DeveloperManage`, `ResourceOwner`. | `CloudClusterAdmin` |
| `default_partitions_count` | Partitions for topics that do not override it. | `1` |
| `min_insync_replicas` | `min.insync.replicas` on every topic. | `"2"` |
| `cdc_retention_ms` | `retention.ms` of the compacted CDC topics. | `"1209600000"` (14 days) |
| `event_retention_ms` | `retention.ms` of the retained event topics. | `"2592000000"` (30 days) |
| `max_message_bytes` | `max.message.bytes` on every topic. | `"2097164"` |

Topic inventory lives in `locals.tf` rather than in variables, because it is a property of
the pipeline rather than of the environment: dev and production get the same topics with
different prefixes. Move it to a variable if that is not true for you.

## Installation

```bash
git clone <repository-url> terraform-confluent-cloud
cd terraform-confluent-cloud

cp backend.hcl.example backend.hcl            # then edit
cp terraform.tfvars.example terraform.tfvars  # then edit

terraform init -backend-config=backend.hcl
```

Credentials are best passed as environment variables, so they never reach a file:

```bash
export TF_VAR_confluent_cloud_api_key="..."
export TF_VAR_confluent_cloud_api_secret="..."
```

## Usage

```bash
terraform plan  -var environment=dev
terraform apply -var environment=dev

# Same configuration, different environment and different state key
terraform init -reconfigure \
  -backend-config=backend.hcl \
  -backend-config="key=confluent-cloud/prod/terraform.tfstate"
terraform plan -var environment=prod
```

Inspect what exists:

```bash
terraform output topic_count
terraform output cdc_topic_names

# The generated Kafka API key, for a producer or a connector
terraform output -raw kafka_api_key
terraform output -raw kafka_api_secret
```

### Adding a topic

One line in the relevant map in `locals.tf`:

```hcl
cdc_topics = {
  # ...
  "order_refunds" = {}
}
```

With a different partition count or a different policy:

```hcl
"order_refunds" = { partitions_count = 6 }
"audit_trail"   = { config = { "retention.ms" = "31536000000" } }  # 1 year
```

### Adopting topics that already exist

Creating a topic that is already there fails. Import it instead, keyed by cluster and
topic name:

```hcl
import {
  to = module.cdc_topics.confluent_kafka_topic.this["orders"]
  id = "lkc-abc123/sales.dev.cdc.orders"
}
```

Then `terraform plan` shows the difference between the live topic and this configuration,
which is the point: it surfaces the drift a hand-managed topic has accumulated.

### Rotating the Kafka API key

```bash
terraform apply -replace='confluent_api_key.topic_manager' -var environment=dev
```

## Topic groups and configuration presets

Three module instances, three prefixes.

| Group | Prefix | Preset | Contents |
|---|---|---|---|
| `cdc_topics` | `<domain>.<env>.cdc.` | compacted | 18 topics, one per replicated source table, plus the connector's own `change_log` which opts out of compaction |
| `producer_topics` | `<domain>.<env>.events.` | retained | 3 topics written by application producers |
| `stream_topics` | `<domain>.<env>.streams.` | retained | 1 topic holding stream-processing output |

**Compacted** is for CDC latest-state topics. The record key is the primary key of the
source row, so compaction collapses a row's history to its current value and a delete
becomes a tombstone. `delete.retention.ms` is 24 hours: a tombstone has to outlive the
longest plausible consumer downtime, because a consumer that was offline for longer never
observes the delete and keeps a row the source no longer has. `retention.ms` bounds how
long superseded versions survive, which is what determines how far back a new consumer can
rebuild state. Compaction only works on keyed records; a compacted topic whose producer
writes null keys grows forever, and no Terraform configuration can enforce that contract.

**Retained** is for append-only event topics. Records expire on time rather than being
collapsed by key, so history is preserved for the retention window and then dropped.

Both inherit `min.insync.replicas = 2`, which on a three-replica cluster means a producer
using `acks=all` survives one broker loss and still refuses to acknowledge a write only one
replica holds.

## Project structure

```
terraform-confluent-cloud/
├── versions.tf                     Terraform and provider constraints, partial S3 backend
├── providers.tf                    Confluent provider, credentials from variables
├── variables.tf                    Inputs, with validation
├── locals.tf                       Config presets and the topic inventory
├── main.tf                         Lookups, service account, API key, three module calls
├── outputs.tf                      IDs, endpoints, topic names, generated credentials
├── terraform.tfvars.example
├── backend.hcl.example
├── .github/workflows/ci.yml        fmt, validate, TFLint, Trivy, committed-secret guard
├── modules/
│   └── topics/
│       ├── README.md               Inputs, outputs and the sharp edges
│       ├── versions.tf
│       ├── variables.tf            Typed topic map with optional attributes
│       ├── main.tf                 One resource, for_each over the map
│       └── outputs.tf
└── examples/
    ├── minimal/                    The module alone, against an existing cluster and key
    └── complete/                   The whole root configuration
```

## Tightening the role binding

`CloudClusterAdmin` is what the original used and is the least effort, but it grants far
more than topic management on the whole cluster. The tighter option is `DeveloperManage`
scoped to a topic prefix, so the service account can only manage the topics of its own
domain:

```hcl
resource "confluent_role_binding" "topic_manager" {
  principal = "User:${confluent_service_account.topic_manager.id}"
  role_name = "DeveloperManage"
  crn_pattern = format(
    "%s/kafka=%s/topic=%s.%s.*",
    data.confluent_kafka_cluster.this.rbac_crn,
    data.confluent_kafka_cluster.this.id,
    var.domain,
    var.environment,
  )
}
```

Left at `CloudClusterAdmin` by default because the prefix-scoped CRN pattern has to match
the naming convention exactly and silently grants nothing when it does not, which is a
confusing first run. Switch to it once the naming is settled.

## Testing

There is no unit test framework here. What CI actually checks:

```bash
terraform fmt -check -recursive -diff

terraform init -backend=false && terraform validate
terraform -chdir=modules/topics init -backend=false && terraform -chdir=modules/topics validate
terraform -chdir=examples/minimal init -backend=false && terraform -chdir=examples/minimal validate
terraform -chdir=examples/complete init -backend=false && terraform -chdir=examples/complete validate

tflint --recursive
trivy config .
```

`validate` catches type errors, unknown arguments and bad references without contacting
Confluent Cloud. It does not catch a plan that would destroy a topic: only reading the
plan does that, which is why CI plans but never applies.

For real verification of behaviour, `terraform plan` against a throwaway Confluent Cloud
environment is the only honest test, since the provider talks to a hosted API with no
local emulator.

## Limitations and notes

- **The Kafka API secret is in state in plain text.** `sensitive = true` only redacts CLI
  output. Encrypt the state bucket, restrict who can read it, and treat state as a secret.
- **Topics are managed over the cluster REST endpoint**, so Terraform needs network
  reachability to it. A cluster with private networking needs the runner inside the VPC or
  a peered network.
- **Removing a map entry destroys the topic and its data.** Intended, but it means a
  careless edit is a data-loss event. Read the plan. For topics that must never be
  destroyed, add `prevent_destroy` to the resource; it cannot be driven from a variable.
- **Partition counts only go up.** Lowering one plans a replacement rather than an in-place
  update.
- **The provider is pinned with `~> 2.83`.** The `1.x` to `2.x` upgrade renamed arguments,
  so a wider constraint is not safe. Check the provider changelog before widening it.
- **No cluster, environment, schema or connector management.** Deliberately out of scope:
  topic churn is frequent and low risk, cluster churn is rare and high risk, and they
  should not share a state file. Schemas and ACLs would be reasonable additions and are not
  here.
- **Topic inventory lives in `locals.tf`, not in a variable.** That suits a pipeline whose
  topics are the same in every environment. Promote it to a variable if your environments
  differ.
- **CI plans but never applies.** Auto-applying on a branch push is how topics get deleted
  by accident. Apply should be a manual, environment-gated job.

## License

MIT. See [LICENSE](LICENSE).

Copyright (c) 2026 Ivan Fernandez García
