variable "account_id" {
  type = string
}

variable "zone_id" {
  type = string
}

variable "domain" {
  description = "Apex domain, e.g. example.com"
  type        = string
}

variable "tunnel_name" {
  type    = string
  default = "aevia"
}

variable "tunnel_secret" {
  description = "Base64, >=32 bytes. Supply from SOPS, never commit."
  type        = string
  sensitive   = true
}

variable "ingress_service" {
  description = "In-cluster address cloudflared forwards everything to (the gateway/ingress Service)."
  type        = string
  default     = "http://ingress.ingress.svc.cluster.local:80"
}

variable "services" {
  description = "Catalog services to publish: name => {exposure, apex, aliases}. Rendered from catalog/services.yml by the caller."
  type = map(object({
    exposure = string
    apex     = optional(bool, false)
    access_ip_bypass = optional(list(string), []) # CIDRs that skip the login for this host (e.g. Anthropic's outbound range for an MCP server that has its own OAuth)
    access_bypass = optional(list(string), []) # path patterns of a gated host that skip the browser login (e.g. git smart-HTTP); the app must authenticate itself
    gate     = optional(string, "") # "access" = Cloudflare Access app (var.access_emails) is created before the DNS record
    aliases  = optional(list(string), []) # extra subdomains routed through the tunnel; their DNS records are managed elsewhere
  }))
}

variable "access_emails" {
  description = "Operator emails allowed through Cloudflare Access for services with gate = access."
  type        = list(string)
  default     = []
}

variable "authentik_client_secret" {
  description = "OIDC client secret of the Authentik provider `cloudflare-access` (blueprint in gitops/base/platform). Empty = no Authentik login method."
  type        = string
  default     = ""
  sensitive   = true
}

variable "authentik_url" {
  description = "Public base URL of Authentik."
  type        = string
  default     = "https://authentik.maxrommel.de"
}
