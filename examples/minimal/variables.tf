variable "confluent_cloud_api_key" {
  type      = string
  sensitive = true
}

variable "confluent_cloud_api_secret" {
  type      = string
  sensitive = true
}

variable "kafka_cluster_id" {
  type        = string
  description = "ID of an existing Kafka cluster, for example lkc-abc123."
}

variable "cluster_rest_endpoint" {
  type        = string
  description = "REST endpoint of that cluster."
}

variable "kafka_api_key" {
  type      = string
  sensitive = true
}

variable "kafka_api_secret" {
  type      = string
  sensitive = true
}
