variable "kafka_cluster_id" {
  type        = string
  description = "ID of the Kafka cluster the topics are created in."
}

variable "cluster_rest_endpoint" {
  type        = string
  description = "REST endpoint of the Kafka cluster. The provider manages topics over this API, not over the Kafka protocol."
}

variable "api_key" {
  type        = string
  description = "Kafka API key used to manage the topics."
  sensitive   = true
}

variable "api_secret" {
  type        = string
  description = "Secret of the Kafka API key."
  sensitive   = true
}

variable "topic_prefix" {
  type        = string
  description = <<-EOT
    Prefix prepended to every map key to form the topic name. Include the trailing
    separator, for example "sales.dev.cdc.".
  EOT
  default     = ""
}

variable "default_partitions_count" {
  type        = number
  description = "Partition count for topics that do not set their own."
  default     = 1

  validation {
    condition     = var.default_partitions_count >= 1
    error_message = "default_partitions_count must be at least 1."
  }
}

variable "default_config" {
  type        = map(string)
  description = <<-EOT
    Topic configuration applied to every topic in this module instance. A topic's own
    `config` is merged over it, so a topic can override individual settings without
    restating the rest.
  EOT
  default     = {}
}

variable "topics" {
  type = map(object({
    partitions_count = optional(number)
    config           = optional(map(string), {})
  }))
  description = <<-EOT
    Topics to create, keyed by the name suffix that follows `topic_prefix`.

    The key is used as the `for_each` key, so it is what identifies the resource in
    state. Renaming a key destroys and recreates the topic; use `terraform state mv`
    to rename without data loss.

      topics = {
        "orders"      = {}                                            # inherits everything
        "order_lines" = { partitions_count = 8 }                      # more partitions
        "change_log"  = { config = { "cleanup.policy" = "delete" } }   # different policy
      }
  EOT

  validation {
    condition = alltrue([
      for name in keys(var.topics) : can(regex("^[a-zA-Z0-9._-]+$", name))
    ])
    error_message = "Topic names may only contain letters, digits, dots, underscores and hyphens."
  }

  validation {
    condition = alltrue([
      for name, topic in var.topics :
      topic.partitions_count == null || try(topic.partitions_count >= 1, false)
    ])
    error_message = "partitions_count must be at least 1 when set."
  }
}
