variable "name" {
  description = "The name of the Automation account."
  type        = string

  validation {
    condition     = length(var.name) >= 6 && length(var.name) <= 50 && can(regex("^[a-zA-Z][a-zA-Z0-9-]*[a-zA-Z0-9]$", var.name))
    error_message = "The Automation account name must be 6-50 characters, start with a letter, end alphanumeric and contain only letters, numbers and hyphens."
  }
}

variable "resource_group_name" {
  description = "The resource group into which the account is deployed."
  type        = string
}

variable "location" {
  description = "The Azure location into which the account is deployed."
  type        = string
}

variable "sku_name" {
  description = "The SKU of the account: Basic (pay per job minute) or Free (500 job minutes a month, for non-production use)."
  type        = string
  default     = "Basic"

  validation {
    condition     = contains(["Basic", "Free"], var.sku_name)
    error_message = "sku_name must be Basic or Free."
  }
}

variable "local_authentication_enabled" {
  description = "Whether the account's keys may be used to start jobs. Keep disabled so Microsoft Entra ID and RBAC are the only path - callers hold Automation Job Operator or Automation Operator instead of a key."
  type        = bool
  default     = false
}

variable "public_network_access_enabled" {
  description = "Whether the account's endpoints are reachable over the public internet. Keep disabled and reach them through private endpoints (the Webhook and DSCAndHybridWorker subresources, resolved by privatelink.azure-automation.net)."
  type        = bool
  default     = false
}

variable "user_assigned_identity_ids" {
  description = "User-assigned identity IDs attached to the account alongside its system-assigned identity, e.g. an identity the runbooks' targets already trust. Leave empty for the system-assigned identity alone."
  type        = list(string)
  default     = []
}

variable "customer_managed_key" {
  description = "Encrypts the account's secure assets with a customer-managed key. identity_id must be one of user_assigned_identity_ids, granted wrap and unwrap on a purge-protected vault. Leave null for platform-managed keys."
  type = object({
    key_vault_key_id = string
    identity_id      = string
  })
  default = null

  validation {
    condition     = var.customer_managed_key == null || contains(var.user_assigned_identity_ids, try(var.customer_managed_key.identity_id, ""))
    error_message = "customer_managed_key.identity_id must be one of user_assigned_identity_ids: the account unwraps the key with an identity it has attached, not with its system-assigned identity and not with one it never joined."
  }
}

variable "runbooks" {
  description = <<-EOT
    Runbooks in the account, keyed by runbook name. Supply either content - the script itself, typically read from the repository with file() - or publish_content_link, a URI the service imports from.

    Never put a credential in a runbook's content: it is stored in the account and in Terraform state. Fetch secrets at runtime from a key vault with the account's managed identity instead.

    Python2 and the older PowerShell runtimes are accepted but retire on 30 September 2026: runbooks on a retired runtime keep running in a reduced-support state, with no security updates and possibly capped at a single instance. Prefer Python3 and PowerShell72 for anything new.
  EOT

  type = map(object({
    runbook_type = optional(string, "PowerShell72")
    description  = optional(string)
    log_verbose  = optional(bool, false)
    log_progress = optional(bool, true)
    content      = optional(string)
    publish_content_link = optional(object({
      uri     = string
      version = optional(string)
    }))
  }))

  default = {}

  validation {
    condition = alltrue([
      for name, runbook in var.runbooks :
      contains(["PowerShell", "PowerShell72", "PowerShellWorkflow", "Python2", "Python3", "Graph", "GraphPowerShell", "GraphPowerShellWorkflow", "Script"], runbook.runbook_type)
    ])
    error_message = "runbook_type must be one of PowerShell, PowerShell72, PowerShellWorkflow, Python2, Python3, Graph, GraphPowerShell, GraphPowerShellWorkflow or Script."
  }

  validation {
    condition = alltrue([
      for name, runbook in var.runbooks :
      (runbook.content == null) != (runbook.publish_content_link == null)
    ])
    error_message = "Every runbook must carry either content or publish_content_link, not both and not neither."
  }

  # Terraform's map keys are distinct case-sensitively; Azure Resource
  # Manager compares names case-insensitively. Cleanup and cleanup are
  # therefore two runbooks to the for_each and one to the account, so
  # both are planned and the second to apply collides with the first.
  validation {
    condition     = length(distinct([for name, runbook in var.runbooks : lower(name)])) == length(var.runbooks)
    error_message = "Runbook names must be unique within the account, ignoring case: Azure Resource Manager compares resource names case-insensitively, so two keys differing only in capitalisation name the same runbook."
  }
}

variable "schedules" {
  description = <<-EOT
    Schedules in the account, keyed by schedule name. Leave start_time null unless a schedule must begin at a particular moment: the provider then starts it seven minutes from creation, which always satisfies the five-minute minimum Azure enforces.

    A pinned start_time is an RFC3339 timestamp that must still be at least five minutes in the future when the apply runs. The module checks the format but deliberately does not compare it against the clock - a time-based rule would make the same configuration plan differently from one hour to the next, and would fail applies of already-deployed schedules once the pinned moment passed. Pin one only where the start moment matters, and move it on when it ages out.

    week_days applies to the Week frequency, month_days and monthly_occurrence to Month; the others are ignored. A OneTime schedule takes no interval.
  EOT

  type = map(object({
    frequency   = string
    interval    = optional(number, 1)
    timezone    = optional(string, "Etc/UTC")
    start_time  = optional(string)
    expiry_time = optional(string)
    description = optional(string)
    week_days   = optional(list(string))
    month_days  = optional(list(number))
    monthly_occurrence = optional(object({
      day        = string
      occurrence = number
    }))
  }))

  default = {}

  validation {
    condition = alltrue([
      for name, schedule in var.schedules :
      contains(["OneTime", "Hour", "Day", "Week", "Month"], schedule.frequency)
    ])
    error_message = "A schedule's frequency must be OneTime, Hour, Day, Week or Month."
  }

  validation {
    condition = alltrue([
      for name, schedule in var.schedules :
      schedule.frequency == "OneTime" || (
        schedule.interval != null &&
        schedule.interval >= 1 &&
        floor(schedule.interval) == schedule.interval
      )
    ])
    error_message = "A recurring schedule needs an interval that is a whole number of at least 1: the interval counts hours, days, weeks or months, none of which Azure Automation divides."
  }

  # Each frequency has its own ceiling, roughly a period of the next
  # unit up: 23 hours, 365 days, 52 weeks, 12 months.
  validation {
    condition = alltrue([
      for name, schedule in var.schedules :
      schedule.frequency == "OneTime" || schedule.interval == null || schedule.interval <= lookup({
        Hour  = 23
        Day   = 365
        Week  = 52
        Month = 12
      }, schedule.frequency, 1)
    ])
    error_message = "A schedule's interval exceeds what its frequency allows: at most 23 for Hour, 365 for Day, 52 for Week and 12 for Month."
  }

  # A format check rather than a comparison against the clock: the
  # latter would make a plan's result depend on when it ran.
  validation {
    condition = alltrue([
      for name, schedule in var.schedules :
      schedule.start_time == null || can(timeadd(coalesce(schedule.start_time, "1970-01-01T00:00:00Z"), "0s"))
    ])
    error_message = "start_time must be an RFC3339 timestamp, e.g. 2030-01-01T22:00:00Z. Leave it null to have the schedule start seven minutes after it is created."
  }

  validation {
    condition = alltrue([
      for name, schedule in var.schedules :
      schedule.expiry_time == null || can(timeadd(coalesce(schedule.expiry_time, "1970-01-01T00:00:00Z"), "0s"))
    ])
    error_message = "expiry_time must be an RFC3339 timestamp, e.g. 2031-01-01T22:00:00Z."
  }

  validation {
    condition = alltrue([
      for name, schedule in var.schedules :
      schedule.start_time == null || schedule.expiry_time == null ||
      try(timecmp(coalesce(schedule.expiry_time, ""), coalesce(schedule.start_time, "")) > 0, false)
    ])
    error_message = "expiry_time must be later than start_time: a schedule that expires before it starts never runs."
  }

  validation {
    condition = alltrue([
      for name, schedule in var.schedules :
      schedule.week_days == null || alltrue([
        for day in coalesce(schedule.week_days, []) :
        contains(["Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday"], day)
      ])
    ])
    error_message = "Every entry in week_days must be a day name: Monday, Tuesday, Wednesday, Thursday, Friday, Saturday or Sunday."
  }

  validation {
    condition = alltrue([
      for name, schedule in var.schedules :
      schedule.month_days == null || alltrue([
        for day in coalesce(schedule.month_days, []) :
        floor(day) == day && ((day >= 1 && day <= 31) || day == -1)
      ])
    ])
    error_message = "Every entry in month_days must be a whole number from 1 to 31, or -1 for the last day of the month: they select calendar days, which do not divide."
  }

  validation {
    condition = alltrue([
      for name, schedule in var.schedules :
      schedule.monthly_occurrence == null || contains(["Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday"], schedule.monthly_occurrence.day)
    ])
    error_message = "monthly_occurrence.day must be a day name, e.g. Monday."
  }

  validation {
    condition = alltrue([
      for name, schedule in var.schedules :
      schedule.monthly_occurrence == null || (
        schedule.monthly_occurrence.occurrence >= -1 &&
        schedule.monthly_occurrence.occurrence <= 5 &&
        schedule.monthly_occurrence.occurrence != 0 &&
        floor(schedule.monthly_occurrence.occurrence) == schedule.monthly_occurrence.occurrence
      )
    ])
    error_message = "monthly_occurrence.occurrence must be a whole number from 1 to 5 for the first to fifth week, or -1 for the last: it counts weeks, which do not divide."
  }

  # The same case-insensitive collision the runbooks map has: schedules
  # are child resources of the account and named the same way.
  validation {
    condition     = length(distinct([for name, schedule in var.schedules : lower(name)])) == length(var.schedules)
    error_message = "Schedule names must be unique within the account, ignoring case: Azure Resource Manager compares resource names case-insensitively, so two keys differing only in capitalisation name the same schedule."
  }
}

variable "job_schedules" {
  description = "Links between runbooks and schedules, keyed by an arbitrary label. runbook_name and schedule_name must be keys of the runbooks and schedules variables. hybrid_worker_group_name runs the job on a hybrid worker inside the network instead of the Azure sandbox - which is what a runbook acting on private resources needs."
  type = map(object({
    runbook_name             = string
    schedule_name            = string
    parameters               = optional(map(string))
    hybrid_worker_group_name = optional(string)
  }))

  default = {}

  validation {
    condition = alltrue([
      for label, link in var.job_schedules :
      contains(keys(var.runbooks), link.runbook_name)
    ])
    error_message = "Every job schedule's runbook_name must be a key of the runbooks variable."
  }

  validation {
    condition = alltrue([
      for label, link in var.job_schedules :
      contains(keys(var.schedules), link.schedule_name)
    ])
    error_message = "Every job schedule's schedule_name must be a key of the schedules variable."
  }

  # Azure Automation normalises parameter names to lower case, so a
  # mixed-case key here fails to bind the runbook's parameter.
  validation {
    condition = alltrue([
      for label, link in var.job_schedules :
      alltrue([for key in keys(coalesce(link.parameters, {})) : key == lower(key)])
    ])
    error_message = "Every key in a job schedule's parameters must be lower case, whatever case the runbook declares: Azure Automation normalises parameter names, and a mixed-case key binds to nothing. The values are unaffected."
  }
}

variable "log_analytics_workspace_id" {
  description = "The ID of a Log Analytics workspace to send diagnostics to. Leave null to skip diagnostics."
  type        = string
  default     = null
}

variable "enable_diagnostics" {
  description = "Whether to create the diagnostic setting. Defaults to creating it when log_analytics_workspace_id is set. Set explicitly when the workspace is created in the same apply: its ID is unknown at plan time, so it cannot decide whether the setting exists."
  type        = bool
  default     = null

  validation {
    condition     = var.enable_diagnostics != true || var.log_analytics_workspace_id != null
    error_message = "enable_diagnostics requires log_analytics_workspace_id to be set."
  }
}

variable "tags" {
  description = "Tags applied to the account and its runbooks."
  type        = map(string)
  default     = {}
}
