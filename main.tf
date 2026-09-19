# ---------------------------------------------------------------------------
# Existing infrastructure
#
# The environment and the cluster are looked up rather than created. Cluster
# lifecycle has a much larger blast radius than topic lifecycle, so it belongs
# in a separate configuration and a separate state file: a careless `destroy`
# here should not be able to take a cluster with it.
# ---------------------------------------------------------------------------

data "confluent_environment" "this" {
  display_name = var.environment
}

data "confluent_kafka_cluster" "this" {
  display_name = var.cluster_name

  environment {
    id = data.confluent_environment.this.id
  }
}

# ---------------------------------------------------------------------------
# Managed identity
#
# Terraform creates its own service account and its own Kafka API key, so the
# only credential supplied from outside is the Cloud API key in
# `confluent_cloud_api_key`. The Kafka-level key never leaves Terraform state,
# is never typed into a variable file, and is rotated by tainting one resource.
# ---------------------------------------------------------------------------

resource "confluent_service_account" "topic_manager" {
  display_name = local.service_account_name
  description  = "Managed by Terraform. Owns the topics of the ${var.domain} domain in ${var.environment}."
}

resource "confluent_role_binding" "topic_manager" {
  principal   = "User:${confluent_service_account.topic_manager.id}"
  role_name   = var.cluster_role
  crn_pattern = data.confluent_kafka_cluster.this.rbac_crn
}

resource "confluent_api_key" "topic_manager" {
  display_name = "${local.service_account_name}-kafka-api-key"
  description  = "Kafka API key owned by the ${local.service_account_name} service account."

  owner {
    id          = confluent_service_account.topic_manager.id
    api_version = confluent_service_account.topic_manager.api_version
    kind        = confluent_service_account.topic_manager.kind
  }

  managed_resource {
    id          = data.confluent_kafka_cluster.this.id
    api_version = data.confluent_kafka_cluster.this.api_version
    kind        = data.confluent_kafka_cluster.this.kind

    environment {
      id = data.confluent_environment.this.id
    }
  }

  # The role binding has to exist before the key is used, otherwise the first
  # topic creation races it and fails with an authorisation error.
  depends_on = [confluent_role_binding.topic_manager]
}

# ---------------------------------------------------------------------------
# Topics
#
# Three instances of the same module. They differ only in their prefix, their
# inventory and which config preset they start from, which is exactly the kind
# of variation a module is for.
# ---------------------------------------------------------------------------

module "cdc_topics" {
  source = "./modules/topics"

  kafka_cluster_id      = data.confluent_kafka_cluster.this.id
  cluster_rest_endpoint = data.confluent_kafka_cluster.this.rest_endpoint
  api_key               = confluent_api_key.topic_manager.id
  api_secret            = confluent_api_key.topic_manager.secret

  topic_prefix             = "${var.domain}.${var.environment}.cdc."
  default_partitions_count = var.default_partitions_count
  default_config           = local.compacted_config
  topics                   = local.cdc_topics
}

module "producer_topics" {
  source = "./modules/topics"

  kafka_cluster_id      = data.confluent_kafka_cluster.this.id
  cluster_rest_endpoint = data.confluent_kafka_cluster.this.rest_endpoint
  api_key               = confluent_api_key.topic_manager.id
  api_secret            = confluent_api_key.topic_manager.secret

  topic_prefix             = "${var.domain}.${var.environment}.events."
  default_partitions_count = var.default_partitions_count
  default_config           = local.retained_config
  topics                   = local.producer_topics
}

module "stream_topics" {
  source = "./modules/topics"

  kafka_cluster_id      = data.confluent_kafka_cluster.this.id
  cluster_rest_endpoint = data.confluent_kafka_cluster.this.rest_endpoint
  api_key               = confluent_api_key.topic_manager.id
  api_secret            = confluent_api_key.topic_manager.secret

  topic_prefix             = "${var.domain}.${var.environment}.streams."
  default_partitions_count = var.default_partitions_count
  default_config           = local.retained_config
  topics                   = local.stream_topics
}
