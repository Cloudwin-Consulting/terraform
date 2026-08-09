terraform {
  required_version = ">= 1.9.0"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.0"
    }
  }
}

# An Azure Virtual Desktop scaling plan for pooled host pools: starts
# and deallocates session hosts on the schedules below so capacity
# follows the working day. The Azure Virtual Desktop service principal
# must hold the Desktop Virtualization Power On Off Contributor role
# on the session hosts' scope (e.g. their resource group) before the
# plan can manage them - callers grant it through the
# rbac-role-assignment module.
resource "azurerm_virtual_desktop_scaling_plan" "this" {
  name                = var.name
  resource_group_name = var.resource_group_name
  location            = var.location
  friendly_name       = var.friendly_name
  description         = var.description
  time_zone           = var.time_zone
  exclusion_tag       = var.exclusion_tag
  tags                = var.tags

  dynamic "schedule" {
    for_each = var.schedules == null ? local.default_schedules : var.schedules

    content {
      name         = schedule.value.name
      days_of_week = schedule.value.days_of_week

      ramp_up_start_time                 = schedule.value.ramp_up_start_time
      ramp_up_load_balancing_algorithm   = schedule.value.ramp_up_load_balancing_algorithm
      ramp_up_minimum_hosts_percent      = schedule.value.ramp_up_minimum_hosts_percent
      ramp_up_capacity_threshold_percent = schedule.value.ramp_up_capacity_threshold_percent

      peak_start_time               = schedule.value.peak_start_time
      peak_load_balancing_algorithm = schedule.value.peak_load_balancing_algorithm

      ramp_down_start_time                 = schedule.value.ramp_down_start_time
      ramp_down_load_balancing_algorithm   = schedule.value.ramp_down_load_balancing_algorithm
      ramp_down_minimum_hosts_percent      = schedule.value.ramp_down_minimum_hosts_percent
      ramp_down_capacity_threshold_percent = schedule.value.ramp_down_capacity_threshold_percent
      ramp_down_force_logoff_users         = schedule.value.ramp_down_force_logoff_users
      ramp_down_wait_time_minutes          = schedule.value.ramp_down_wait_time_minutes
      ramp_down_notification_message       = schedule.value.ramp_down_notification_message
      ramp_down_stop_hosts_when            = schedule.value.ramp_down_stop_hosts_when

      off_peak_start_time               = schedule.value.off_peak_start_time
      off_peak_load_balancing_algorithm = schedule.value.off_peak_load_balancing_algorithm
    }
  }

  # Host pools the plan scales, keyed by a static label so pools
  # created in the same apply - whose IDs are unknown at plan time -
  # can still be associated.
  dynamic "host_pool" {
    for_each = var.host_pools

    content {
      hostpool_id          = host_pool.value.host_pool_id
      scaling_plan_enabled = host_pool.value.scaling_plan_enabled
    }
  }
}

locals {
  # A worked full-week schedule. Weekdays: hosts ramp up ahead of the
  # working day, scale on demand through it, then drain in the evening
  # - remaining users are signed out after the 30 minute warning, so
  # disconnected sessions cannot hold a host up overnight. Weekends
  # need their own schedule - days no schedule covers get no autoscale
  # at all - and run on demand only: no host is kept warm, and
  # anything started (e.g. by start VM on connect) drains again the
  # same way.
  default_schedules = [
    {
      name         = "weekdays"
      days_of_week = ["Monday", "Tuesday", "Wednesday", "Thursday", "Friday"]

      ramp_up_start_time                 = "07:00"
      ramp_up_load_balancing_algorithm   = "BreadthFirst"
      ramp_up_minimum_hosts_percent      = 25
      ramp_up_capacity_threshold_percent = 60

      peak_start_time               = "09:00"
      peak_load_balancing_algorithm = "BreadthFirst"

      ramp_down_start_time                 = "18:00"
      ramp_down_load_balancing_algorithm   = "DepthFirst"
      ramp_down_minimum_hosts_percent      = 10
      ramp_down_capacity_threshold_percent = 90
      ramp_down_force_logoff_users         = true
      ramp_down_wait_time_minutes          = 30
      ramp_down_notification_message       = "This desktop is scaling down for the evening. Please save your work; disconnected sessions will be signed out in 30 minutes."
      ramp_down_stop_hosts_when            = "ZeroSessions"

      off_peak_start_time               = "20:00"
      off_peak_load_balancing_algorithm = "DepthFirst"
    },
    {
      name         = "weekends"
      days_of_week = ["Saturday", "Sunday"]

      ramp_up_start_time                 = "09:00"
      ramp_up_load_balancing_algorithm   = "DepthFirst"
      ramp_up_minimum_hosts_percent      = 0
      ramp_up_capacity_threshold_percent = 90

      peak_start_time               = "10:00"
      peak_load_balancing_algorithm = "DepthFirst"

      ramp_down_start_time                 = "16:00"
      ramp_down_load_balancing_algorithm   = "DepthFirst"
      ramp_down_minimum_hosts_percent      = 0
      ramp_down_capacity_threshold_percent = 90
      ramp_down_force_logoff_users         = true
      ramp_down_wait_time_minutes          = 30
      ramp_down_notification_message       = "This desktop is scaling down. Please save your work; disconnected sessions will be signed out in 30 minutes."
      ramp_down_stop_hosts_when            = "ZeroSessions"

      off_peak_start_time               = "18:00"
      off_peak_load_balancing_algorithm = "DepthFirst"
    }
  ]
}
