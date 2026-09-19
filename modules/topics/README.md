# modules/topics

Creates any number of Confluent Cloud Kafka topics from a map, with shared
defaults and per-topic overrides.

One `confluent_kafka_topic` resource with `for_each` replaces one hand-written
block per topic. The inventory becomes data, the behaviour stays in one place,
and a shared setting changes in one edit instead of once per topic.

## Usage

```hcl
module "cdc_topics" {
  source = "./modules/topics"

  kafka_cluster_id      = data.confluent_kafka_cluster.this.id
  cluster_rest_endpoint = data.confluent_kafka_cluster.this.rest_endpoint
  api_key               = confluent_api_key.topic_manager.id
  api_secret            = confluent_api_key.topic_manager.secret

  topic_prefix             = "sales.dev.cdc."
  default_partitions_count = 1

  default_config = {
    "cleanup.policy"      = "compact"
    "retention.ms"        = "1209600000"
    "min.insync.replicas" = "2"
  }

  topics = {
    "orders"      = {}
    "customers"   = {}
    "order_lines" = { partitions_count = 8 }
    "change_log"  = { config = { "cleanup.policy" = "delete" } }
  }
}
```

## Inputs

| Name | Type | Description | Default |
|---|---|---|---|
| `kafka_cluster_id` | `string` | ID of the target Kafka cluster. | required |
| `cluster_rest_endpoint` | `string` | REST endpoint of the cluster. Topics are managed over this API, not over the Kafka protocol. | required |
| `api_key` | `string`, sensitive | Kafka API key used to manage the topics. | required |
| `api_secret` | `string`, sensitive | Secret of that key. | required |
| `topics` | `map(object({ partitions_count = optional(number), config = optional(map(string), {}) }))` | Topics to create, keyed by the name suffix after `topic_prefix`. | required |
| `topic_prefix` | `string` | Prefix prepended to each key. Include the trailing separator. | `""` |
| `default_partitions_count` | `number` | Partition count for topics that do not set their own. | `1` |
| `default_config` | `map(string)` | Config applied to every topic; a topic's own `config` is merged over it. | `{}` |

## Outputs

| Name | Description |
|---|---|
| `topic_names` | Full topic names, keyed by map key. |
| `topic_ids` | Terraform resource IDs, keyed by map key. |
| `topic_count` | Number of topics managed. |
| `partitions_by_topic` | Resolved partition count per topic, after defaults and overrides. |

## How the merge resolves

For each entry, `config = merge(var.default_config, each.value.config)` and
`partitions_count = coalesce(each.value.partitions_count, var.default_partitions_count)`.

So a topic inherits everything by default, overrides only the keys it names, and
anything absent from both the topic and `default_config` is left at the broker
default rather than pinned by this module.

## Things to know before using it

**The map key is the resource identity.** Terraform addresses these resources as
`module.x.confluent_kafka_topic.this["orders"]`. Renaming a key is a destroy and
recreate, which on a Kafka topic means losing its data. Rename without data loss
with:

```bash
terraform state mv \
  'module.cdc_topics.confluent_kafka_topic.this["old_name"]' \
  'module.cdc_topics.confluent_kafka_topic.this["new_name"]'
```

**Partition counts go up, not down.** Raising `partitions_count` is an in-place
update. Lowering it is not supported by Kafka, so Terraform plans a replacement,
which destroys the topic. Check the plan.

**Changing `topic_prefix` renames every topic in the instance**, and therefore
replaces every one of them. Treat the prefix as fixed once there is data.

**Removing an entry from the map destroys that topic.** That is the intent, but
it means a careless edit is a data-loss event. For topics that must never be
destroyed, add `prevent_destroy` to the resource; it cannot be driven from a
variable because `lifecycle` does not accept expressions.

**Compaction needs keyed records.** `cleanup.policy = "compact"` on a topic whose
records have null keys grows forever and never compacts. That is a producer
contract this module cannot enforce.
