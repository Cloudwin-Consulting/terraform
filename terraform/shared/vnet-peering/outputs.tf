output "spoke_to_hub_peering_id" {
  description = "The ID of the spoke to hub peering."
  value       = azurerm_virtual_network_peering.spoke_to_hub.id
}

output "hub_to_spoke_peering_id" {
  description = "The ID of the hub to spoke peering."
  value       = azurerm_virtual_network_peering.hub_to_spoke.id
}
