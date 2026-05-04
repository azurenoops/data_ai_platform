output "platform_ops_action_group_id" {
  description = "Resource ID of the platform_ops action group; empty when alerting is disabled."
  value       = local.alerts_action_id
}
