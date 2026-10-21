variable "hcloud_token" {
  type      = string
  sensitive = true
}

variable "cloudflare_api_token" {
  type      = string
  sensitive = true
}

variable "cloudflare_account_id" {
  type = string
}

variable "cloudflare_zone_id" {
  type = string
}

variable "domain" {
  type = string
}

variable "tunnel_secret" {
  type      = string
  sensitive = true
}

variable "ssh_public_key" {
  type = string
}

variable "ssh_allowed_cidrs" {
  type    = list(string)
  default = []
}

variable "nodes" {
  type = map(object({
    role        = string
    server_type = string
    volume_gb   = optional(number, 0)
  }))
  default = {
    "01" = { role = "control", server_type = "cx33", volume_gb = 0 }
    # "01" = { role = "agent", server_type = "cx33" }  # phase 23
  }
}

variable "access_emails" {
  description = "Operator emails allowed through Cloudflare Access for gated hosts."
  type        = list(string)
  default     = []
}

variable "authentik_cloudflare_secret" {
  description = "OIDC client secret for Cloudflare Access (from the SOPS secret authentik-env, key OIDC_CLOUDFLARE_SECRET)."
  type        = string
  default     = ""
  sensitive   = true
}
