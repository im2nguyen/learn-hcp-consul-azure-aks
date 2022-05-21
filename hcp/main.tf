provider "azurerm" {
  features {}
}

provider "hcp" {}

data "terraform_remote_state" "azure" {
  backend = "local"

  config = {
    path = "../azure/terraform.tfstate"
  }
}

data "azurerm_subscription" "current" {}

data "azurerm_virtual_network" "vnet" {
  name                = data.terraform_remote_state.azure.outputs.azure_vnet_name
  resource_group_name = data.terraform_remote_state.azure.outputs.azure_rg_name
}

resource "hcp_hvn" "hvn" {
  hvn_id         = var.hvn_id
  cloud_provider = "azure"
  region         = var.hvn_region
  cidr_block     = var.hvn_cidr_block
}

resource "hcp_consul_cluster" "main" {
  cluster_id      = var.cluster_id
  hvn_id          = hcp_hvn.hvn.hvn_id
  public_endpoint = true
  tier            = var.tier
}

resource "hcp_consul_cluster_root_token" "token" {
  cluster_id = hcp_consul_cluster.main.id
}

// Step 2 - Set up peering connection: connect Azure VNets to HVN
module "hcp_peering" {
  source  = "hashicorp/hcp-consul/azurerm"
  version = "~> 0.1.0"

  # Required
  tenant_id       = data.azurerm_subscription.current.tenant_id
  subscription_id = data.azurerm_subscription.current.subscription_id
  hvn             = hcp_hvn.hvn
  vnet_rg         = data.terraform_remote_state.azure.outputs.azure_rg_name
  vnet_id         = data.terraform_remote_state.azure.outputs.azure_vnet_id
  subnet_ids      = data.terraform_remote_state.azure.outputs.azure_subnet_ids

  # Optional
  security_group_names = [data.terraform_remote_state.azure.outputs.azure_nsg_name]
  prefix               = var.cluster_id
}

resource "azurerm_network_security_rule" "ingress_gw" {
  name                        = "ingress-gateway"
  priority                    = 200
  direction                   = "Inbound"
  access                      = "Allow"
  protocol                    = "*"
  source_address_prefix       = "*"
  source_port_range           = "*"
  destination_address_prefix  = "*"
  destination_port_range      = "8080"
  resource_group_name         = data.terraform_remote_state.azure.outputs.azure_rg_name
  network_security_group_name = data.terraform_remote_state.azure.outputs.azure_nsg_name
}
