output "topic_names" {
  description = "Full topic names created by this module instance, keyed by the map key."
  value       = { for key, topic in confluent_kafka_topic.this : key => topic.topic_name }
}

output "topic_ids" {
  description = "Terraform resource IDs of the topics, keyed by the map key."
  value       = { for key, topic in confluent_kafka_topic.this : key => topic.id }
}

output "topic_count" {
  description = "Number of topics managed by this module instance."
  value       = length(confluent_kafka_topic.this)
}

output "partitions_by_topic" {
  description = "Resolved partition count per topic, after defaults and overrides."
  value       = { for key, topic in confluent_kafka_topic.this : key => topic.partitions_count }
}
