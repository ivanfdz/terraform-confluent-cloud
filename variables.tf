variable "environment" {
  type        = string
  description = <<-EOT
    Name of the target Confluent Cloud environment. It is also interpolated into the
    topic prefixes, so the same configuration serves every environment with a single
    `-var environment=...`.
  EOT

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{1,30}$", var.environment))
    error_message = "environment must be lowercase alphanumeric with hyphens, 2 to 31 characters."
  }
}

variable "cluster_name" {
  type        = string
  description = <<-EOT
    Display name of an existing Kafka cluster inside the environment. The cluster is
    looked up, not created: cluster lifecycle is usually owned by a separate
    configuration with a different blast radius.
  EOT
}

variable "domain" {
  type        = string
  description = <<-EOT
    Logical domain prefixing every topic name, so several teams can share a cluster
    without colliding. Topic names end up as `<domain>.<environment>.<group>.<name>`.
  EOT
  default     = "sales"

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{1,30}$", var.domain))
    error_message = "domain must be lowercase alphanumeric with hyphens, 2 to 31 characters."
  }
}

variable "confluent_cloud_api_key" {
  type        = string
  description = "Confluent Cloud API key of the service account running Terraform."
  sensitive   = true
}

variable "confluent_cloud_api_secret" {
  type        = string
  description = "Confluent Cloud API secret of the service account running Terraform."
  sensitive   = true
}

variable "service_account_name" {
  type        = string
  description = <<-EOT
    Display name of the service account Terraform creates to own the topics. Confluent
    Cloud requires it to be unique across the organisation, which is why the
    environment is part of the default.
  EOT
  default     = null
}

variable "cluster_role" {
  type        = string
  description = <<-EOT
    Role bound to the managed service account on the cluster. CloudClusterAdmin is
    what the original configuration used and is the least effort; DeveloperManage
    scoped to a topic prefix is the tighter option and is shown in the README.
  EOT
  default     = "CloudClusterAdmin"

  validation {
    condition = contains(
      ["CloudClusterAdmin", "DeveloperManage", "ResourceOwner"],
      var.cluster_role
    )
    error_message = "cluster_role must be CloudClusterAdmin, DeveloperManage or ResourceOwner."
  }
}

variable "default_partitions_count" {
  type        = number
  description = <<-EOT
    Partition count applied to any topic that does not override it. Raising a topic's
    partition count later is an in-place update, lowering it is not supported by Kafka
    and forces a replacement, so this is worth getting roughly right up front.
  EOT
  default     = 1

  validation {
    condition     = var.default_partitions_count >= 1 && var.default_partitions_count <= 1000
    error_message = "default_partitions_count must be between 1 and 1000."
  }
}

variable "min_insync_replicas" {
  type        = string
  description = <<-EOT
    `min.insync.replicas` applied to every topic. 2 on a 3-replica cluster is the
    usual durability choice: a producer using acks=all survives one broker loss and
    still refuses to acknowledge a write that only one replica holds.
  EOT
  default     = "2"
}

variable "cdc_retention_ms" {
  type        = string
  description = <<-EOT
    `retention.ms` of the compacted CDC topics. Compaction keeps the latest value per
    key indefinitely; this bounds how long superseded versions and tombstones survive,
    which is what determines how far back a consumer can rebuild history.
  EOT
  default     = "1209600000" # 14 days
}

variable "event_retention_ms" {
  type        = string
  description = "`retention.ms` of the non-compacted event topics."
  default     = "2592000000" # 30 days
}

variable "max_message_bytes" {
  type        = string
  description = <<-EOT
    `max.message.bytes` applied to every topic. The default is the Confluent Cloud
    Basic/Standard ceiling of 2 MiB plus the record overhead the broker adds.
  EOT
  default     = "2097164"
}
