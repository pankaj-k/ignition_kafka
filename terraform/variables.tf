variable "confluent_cloud_api_key" {
  description = "Confluent Cloud API key (from cloud.confluent.io → API Keys)"
  type        = string
  sensitive   = true
}

variable "confluent_cloud_api_secret" {
  description = "Confluent Cloud API secret"
  type        = string
  sensitive   = true
}

variable "confluent_environment_id" {
  description = "Confluent environment ID (e.g. env-abc123) — found in Confluent Cloud UI URL"
  type        = string
}

variable "confluent_cluster_id" {
  description = "Kafka cluster ID (e.g. lkc-abc123) — found in Cluster → Cluster Settings"
  type        = string
}

variable "confluent_bootstrap_server" {
  description = "Kafka bootstrap server (e.g. pkc-xxxxx.region.provider.confluent.cloud:9092)"
  type        = string
}
