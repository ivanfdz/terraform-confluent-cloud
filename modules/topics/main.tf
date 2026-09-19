# A single resource block for an arbitrary number of topics.
#
# The configuration this replaces had one hand-written `confluent_kafka_topic`
# block per topic: 18 of them in one file, 495 lines, differing only in
# `topic_name`. Every one of the 12 config settings was restated verbatim in
# every block, so changing a retention policy meant 18 identical edits and any
# topic missed silently drifted.
#
# Here the inventory is data (a map) and the behaviour is code (this block), so
# adding a topic is one line and changing a shared setting is one edit.

resource "confluent_kafka_topic" "this" {
  for_each = var.topics

  kafka_cluster {
    id = var.kafka_cluster_id
  }

  topic_name    = "${var.topic_prefix}${each.key}"
  rest_endpoint = var.cluster_rest_endpoint

  partitions_count = coalesce(each.value.partitions_count, var.default_partitions_count)

  # Per-topic settings win over the module default. Anything absent from both is
  # left to the broker default rather than pinned here.
  config = merge(var.default_config, each.value.config)

  credentials {
    key    = var.api_key
    secret = var.api_secret
  }
}
