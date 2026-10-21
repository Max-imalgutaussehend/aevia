provider "hcloud" {
  token = var.hcloud_token
}

provider "cloudflare" {
  api_token = var.cloudflare_api_token
}

locals {
  catalog  = yamldecode(file("${path.root}/../../../../catalog/services.yml"))
  services = { for s in local.catalog.services : s.name => { exposure = s.exposure, apex = try(s.apex, false), aliases = try(s.aliases, []), gate = try(s.gate, ""), access_bypass = try(s.access_bypass, []), access_ip_bypass = try(s.access_ip_bypass, []) } if try(s.hold, "") == "" }
}

module "hetzner" {
  source = "../../modules/hetzner"

  name_prefix       = "aevia"
  ssh_public_key    = var.ssh_public_key
  ssh_allowed_cidrs = var.ssh_allowed_cidrs
  nodes             = var.nodes
}

module "cloudflare" {
  source = "../../modules/cloudflare"

  account_id    = var.cloudflare_account_id
  zone_id       = var.cloudflare_zone_id
  domain        = var.domain
  tunnel_secret = var.tunnel_secret
  services      = local.services
  access_emails = var.access_emails

  authentik_client_secret = var.authentik_cloudflare_secret
}
