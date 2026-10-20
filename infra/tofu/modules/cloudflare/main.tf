terraform {
  required_providers {
    cloudflare = {
      source  = "cloudflare/cloudflare"
      version = "~> 5.0"
    }
  }
}

resource "cloudflare_zero_trust_tunnel_cloudflared" "aevia" {
  account_id    = var.account_id
  name          = var.tunnel_name
  config_src    = "cloudflare"
  tunnel_secret = var.tunnel_secret
}

locals {
  hostnames = {
    for name, s in var.services :
    name => s.apex ? var.domain : "${name}.${var.domain}"
  }
}

locals {
  alias_hostnames = flatten([for s in values(var.services) : [for a in s.aliases : "${a}.${var.domain}"]])
}

# One wildcard-style rule set: every hostname goes to the in-cluster ingress,
# which routes by Host header. Routing logic stays in Kubernetes (ADR-0028).
resource "cloudflare_zero_trust_tunnel_cloudflared_config" "aevia" {
  account_id = var.account_id
  tunnel_id  = cloudflare_zero_trust_tunnel_cloudflared.aevia.id

  config = {
    ingress = concat(
      [for h in concat(values(local.hostnames), local.alias_hostnames) : {
        hostname = h
        service  = var.ingress_service
      }],
      [{ service = "http_status:404" }]
    )
  }
}

locals {
  gated = { for name, s in var.services : name => local.hostnames[name] if s.gate == "access" }
}

# One account-level policy shared by every gated host. Created before any gated DNS record (depends_on below),
# so a host is never reachable without its Access app.
resource "cloudflare_zero_trust_access_policy" "operator" {
  count      = length(local.gated) > 0 ? 1 : 0
  account_id = var.account_id
  name       = "aevia-operator"
  decision   = "allow"
  include    = [for e in var.access_emails : { email = { email = e } }]

  lifecycle {
    precondition {
      condition     = length(var.access_emails) > 0
      error_message = "gate = access needs at least one entry in access_emails; refusing to publish ungated hosts."
    }
  }
}

resource "cloudflare_zero_trust_access_application" "gated" {
  for_each = local.gated

  account_id       = var.account_id
  name             = each.key
  domain           = each.value
  type             = "self_hosted"
  session_duration = "24h"
  policies         = [{ id = cloudflare_zero_trust_access_policy.operator[0].id, precedence = 1 }]
}

resource "cloudflare_dns_record" "service" {
  for_each = local.hostnames

  depends_on = [cloudflare_zero_trust_access_application.gated]

  zone_id = var.zone_id
  name    = each.value
  type    = "CNAME"
  content = "${cloudflare_zero_trust_tunnel_cloudflared.aevia.id}.cfargotunnel.com"
  proxied = true
  ttl     = 1
}

# Authentik as an additional login method for every Access app. The one-time PIN stays available, so a broken
# Authentik cannot lock the operator out; apps without allowed_idps offer all configured methods.
resource "cloudflare_zero_trust_access_identity_provider" "authentik" {
  count      = var.authentik_client_secret == "" ? 0 : 1
  account_id = var.account_id
  name       = "Authentik"
  type       = "oidc"
  config = {
    client_id     = "cloudflare-access"
    client_secret = var.authentik_client_secret
    auth_url      = "${var.authentik_url}/application/o/authorize/"
    token_url     = "${var.authentik_url}/application/o/token/"
    certs_url     = "${var.authentik_url}/application/o/cloudflare-access/jwks/"
    scopes        = ["openid", "email", "profile"]
    pkce_enabled  = true
  }
}
