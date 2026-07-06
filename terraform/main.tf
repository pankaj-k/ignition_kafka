terraform {
  required_providers {
    confluent = {
      source  = "confluentinc/confluent"
      version = "~> 2.0"
    }
  }
}

provider "confluent" {
  cloud_api_key    = var.confluent_cloud_api_key
  cloud_api_secret = var.confluent_cloud_api_secret
}

# Reference the existing cluster — we are not creating it, just managing topics on it
data "confluent_kafka_cluster" "factory" {
  id = var.confluent_cluster_id

  environment {
    id = var.confluent_environment_id
  }
}

locals {
  topics = [
    "factory.assembly",
    "factory.energy",
    "factory.process",
    "factory.packaging",
    "factory.quality",
  ]
}

resource "confluent_kafka_topic" "factory_topics" {
  for_each = toset(local.topics)

  topic_name       = each.key
  partitions_count = 3

  kafka_cluster {
    id = data.confluent_kafka_cluster.factory.id
  }

  rest_endpoint = data.confluent_kafka_cluster.factory.rest_endpoint

  credentials {
    key    = var.confluent_cloud_api_key
    secret = var.confluent_cloud_api_secret
  }
}
