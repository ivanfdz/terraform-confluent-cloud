locals {
  service_account_name = coalesce(
    var.service_account_name,
    "terraform-${var.domain}-${var.environment}"
  )

  # ---------------------------------------------------------------------------
  # Topic configuration presets
  #
  # These are the two shapes that actually exist in this pipeline. They are
  # declared once and merged per topic, which is the whole point of the refactor
  # described in the README: the 18 hand-written resource blocks this replaces
  # repeated these same 12 settings verbatim 18 times.
  # ---------------------------------------------------------------------------

  # Settings that are identical regardless of cleanup policy.
  common_config = {
    "max.message.bytes"                   = var.max_message_bytes
    "min.insync.replicas"                 = var.min_insync_replicas
    "retention.bytes"                     = "-1"
    "segment.bytes"                       = "104857600" # 100 MiB
    "segment.ms"                          = "604800000" # 7 days
    "message.timestamp.type"              = "CreateTime"
    "message.timestamp.difference.max.ms" = "9223372036854775807"
  }

  # Compacted: latest-state CDC topics. The key is the primary key of the source
  # row, so compaction collapses the history of a row down to its current value
  # and a delete becomes a tombstone.
  compacted_config = merge(local.common_config, {
    "cleanup.policy" = "compact"
    "retention.ms"   = var.cdc_retention_ms

    # How long a tombstone survives compaction. It has to exceed the longest
    # plausible consumer downtime, otherwise a consumer that was offline never
    # observes the delete and keeps a row the source no longer has.
    "delete.retention.ms" = "86400000" # 24 hours

    # No forced compaction deadline and no minimum dirty age: let the broker
    # compact whenever a segment rolls.
    "max.compaction.lag.ms" = "9223372036854775807"
    "min.compaction.lag.ms" = "0"
  })

  # Retained: append-only event and stream-processing topics. Records expire on
  # time rather than being collapsed by key.
  retained_config = merge(local.common_config, {
    "cleanup.policy"      = "delete"
    "retention.ms"        = var.event_retention_ms
    "delete.retention.ms" = "86400000"
  })

  # ---------------------------------------------------------------------------
  # Topic inventory
  #
  # Adding a topic is one line in one of these maps. Overriding a setting for a
  # single topic is one nested line, and everything else stays inherited.
  # ---------------------------------------------------------------------------

  # Change-data-capture topics, one per replicated source table.
  cdc_topics = {
    "orders"               = {}
    "order_lines"          = {}
    "order_status_history" = {}
    "customers"            = {}
    "customer_addresses"   = {}
    "products"             = {}
    "product_categories"   = {}
    "price_lists"          = {}
    "warehouses"           = {}
    "stock_levels"         = {}
    "stock_movements"      = {}
    "shipments"            = {}
    "shipment_items"       = {}
    "carriers"             = {}
    "countries"            = {}
    "payment_methods"      = {}
    "invoices"             = {}

    # The connector's own transaction log. It is append-only rather than keyed,
    # so it opts out of compaction and keeps a shorter window. This single
    # override is why per-topic config exists at all.
    "change_log" = {
      config = {
        "cleanup.policy" = "delete"
        "retention.ms"   = "604800000" # 7 days
      }
    }
  }

  # Topics written by application producers. Higher fan-out, so the busy ones
  # raise their partition count above the default.
  producer_topics = {
    "order_events"    = { partitions_count = 8 }
    "customer_events" = { partitions_count = 8 }
    "daily_summary"   = {}
  }

  # Output of the stream-processing layer.
  stream_topics = {
    "orders_enriched" = { partitions_count = 8 }
  }
}
