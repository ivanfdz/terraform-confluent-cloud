# Minimal example: the topic module on its own, against a cluster and an API key
# you already have. Nothing is created except the topics.

terraform {
  required_version = ">= 1.5"

  required_providers {
    confluent = {
      source  = "confluentinc/confluent"
      version = "~> 2.83"
    }
  }
}

provider "confluent" {
  cloud_api_key    = var.confluent_cloud_api_key
  cloud_api_secret = var.confluent_cloud_api_secret
}

module "topics" {
  source = "../../modules/topics"

  kafka_cluster_id      = var.kafka_cluster_id
  cluster_rest_endpoint = var.cluster_rest_endpoint
  api_key               = var.kafka_api_key
  api_secret            = var.kafka_api_secret

  topic_prefix = "example.dev."

  default_partitions_count = 1
  default_config = {
    "cleanup.policy"      = "delete"
    "retention.ms"        = "604800000" # 7 days
    "min.insync.replicas" = "2"
  }

  topics = {
    "orders"    = {}
    "customers" = {}

    # Busier topic: more partitions, everything else inherited.
    "order_events" = { partitions_count = 6 }

    # Different cleanup policy for this one topic. The rest of default_config
    # still applies.
    "order_state" = {
      config = {
        "cleanup.policy" = "compact"
      }
    }
  }
}

output "topic_names" {
  value = module.topics.topic_names
}
