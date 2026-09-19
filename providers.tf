provider "confluent" {
  # Cloud API key of a Confluent Cloud service account with EnvironmentAdmin (or
  # narrower) permissions. This is the only long-lived credential the configuration
  # needs: every Kafka-level credential below is created by Terraform itself.
  cloud_api_key    = var.confluent_cloud_api_key
  cloud_api_secret = var.confluent_cloud_api_secret
}
