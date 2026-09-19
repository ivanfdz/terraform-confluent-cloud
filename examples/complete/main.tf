# Complete example: the root configuration, which looks up an environment and a
# cluster, creates its own service account and Kafka API key, and manages three
# groups of topics.
#
# The root module uses an S3 backend, so this example overrides it to local
# state. That keeps `terraform init` in this directory working without any AWS
# setup.

terraform {
  required_version = ">= 1.5"

  required_providers {
    confluent = {
      source  = "confluentinc/confluent"
      version = "~> 2.83"
    }
  }
}

module "confluent_cloud" {
  source = "../../"

  environment  = "dev"
  cluster_name = "shared-dev-cluster"
  domain       = "sales"

  confluent_cloud_api_key    = var.confluent_cloud_api_key
  confluent_cloud_api_secret = var.confluent_cloud_api_secret

  default_partitions_count = 1
  min_insync_replicas      = "2"
  cdc_retention_ms         = "1209600000"
  event_retention_ms       = "2592000000"
}

output "topic_count" {
  value = module.confluent_cloud.topic_count
}

output "cdc_topic_names" {
  value = module.confluent_cloud.cdc_topic_names
}

output "bootstrap_endpoint" {
  value = module.confluent_cloud.cluster_bootstrap_endpoint
}
