variable "name" {
  description = "The name of the scaling plan."
  type        = string
}

variable "resource_group_name" {
  description = "The resource group into which the scaling plan is deployed."
  type        = string
}

variable "location" {
  description = "The Azure location into which the scaling plan is deployed."
  type        = string
}

variable "friendly_name" {
  description = "The friendly name of the scaling plan."
  type        = string
  default     = null
}

variable "description" {
  description = "A description of the scaling plan."
  type        = string
  default     = null
}

variable "time_zone" {
  description = "The Windows time zone the schedules run in, e.g. GMT Standard Time."
  type        = string
}

variable "exclusion_tag" {
  description = "The name of a tag that excludes a session host from scaling operations when present on the machine. Leave null to scale every host in the associated pools."
  type        = string
  default     = null
}

variable "schedules" {
  description = "The scaling schedules, each covering a set of days with ramp-up, peak, ramp-down and off-peak phases (times are HH:MM in time_zone; load balancing algorithms are BreadthFirst or DepthFirst). Days no schedule covers get no autoscale at all, and the ramp-down warning message and wait only apply when ramp_down_force_logoff_users is true. Leave null for the module's worked full-week default: weekdays ramp up from 07:00, peak from 09:00 and drain from 18:00, signing remaining users out after a 30 minute warning so disconnected sessions cannot hold a host up overnight; weekends keep no host warm and drain on-demand starts the same way."
  type = list(object({
    name         = string
    days_of_week = list(string)

    ramp_up_start_time                 = string
    ramp_up_load_balancing_algorithm   = string
    ramp_up_minimum_hosts_percent      = number
    ramp_up_capacity_threshold_percent = number

    peak_start_time               = string
    peak_load_balancing_algorithm = string

    ramp_down_start_time                 = string
    ramp_down_load_balancing_algorithm   = string
    ramp_down_minimum_hosts_percent      = number
    ramp_down_capacity_threshold_percent = number
    ramp_down_force_logoff_users         = bool
    ramp_down_wait_time_minutes          = number
    ramp_down_notification_message       = string
    ramp_down_stop_hosts_when            = string

    off_peak_start_time               = string
    off_peak_load_balancing_algorithm = string
  }))
  default = null

  validation {
    condition     = var.schedules == null ? true : length(var.schedules) > 0
    error_message = "schedules must contain at least one schedule; leave it null for the default working-week schedule."
  }

  validation {
    condition     = var.schedules == null ? true : alltrue([for schedule in var.schedules : contains(["ZeroSessions", "ZeroActiveSessions"], schedule.ramp_down_stop_hosts_when)])
    error_message = "ramp_down_stop_hosts_when must be ZeroSessions or ZeroActiveSessions."
  }
}

variable "host_pools" {
  description = "The pooled host pools the plan scales, keyed by a static label naming each association, e.g. { avd = { host_pool_id = module.host_pool.id } }. The labels must be known at plan time; the IDs may come from pools deployed in the same apply."
  type = map(object({
    host_pool_id         = string
    scaling_plan_enabled = optional(bool, true)
  }))
  default = {}
}

variable "tags" {
  description = "Tags applied to the scaling plan."
  type        = map(string)
  default     = {}
}
