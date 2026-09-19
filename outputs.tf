output "environment_id" {
  description = "ID of the Confluent Cloud environment that was looked up."
  value       = data.confluent_environment.this.id
}

output "cluster_id" {
  description = "ID of the Kafka cluster that was looked up."
  value       = data.confluent_kafka_cluster.this.id
}

output "cluster_bootstrap_endpoint" {
  description = "Bootstrap endpoint clients connect to."
  value       = data.confluent_kafka_cluster.this.bootstrap_endpoint
}

output "service_account_id" {
  description = "ID of the service account Terraform created to own the topics."
  value       = confluent_service_account.topic_manager.id
}

output "kafka_api_key" {
  description = "Kafka API key created for the managed service account."
  value       = confluent_api_key.topic_manager.id
  sensitive   = true
}

output "kafka_api_secret" {
  description = <<-EOT
    Secret of the Kafka API key. Marked sensitive, so it is redacted in plan and
    apply output, but it is stored in plain text in the state file: encrypt the
    state backend and restrict who can read it.
  EOT
  value       = confluent_api_key.topic_manager.secret
  sensitive   = true
}

output "cdc_topic_names" {
  description = "Names of the compacted CDC topics."
  value       = module.cdc_topics.topic_names
}

output "producer_topic_names" {
  description = "Names of the producer event topics."
  value       = module.producer_topics.topic_names
}

output "stream_topic_names" {
  description = "Names of the stream-processing output topics."
  value       = module.stream_topics.topic_names
}

output "topic_count" {
  description = "Total number of topics managed by this configuration."
  value = (
    module.cdc_topics.topic_count +
    module.producer_topics.topic_count +
    module.stream_topics.topic_count
  )
}
