#!/bin/bash

echo "[Setup-Vault] - Starting Vault setup, VAULT_ADDR and VAULT_TOKEN must be set already"
vault status

# SSH Secrets engine
echo "[Setup-Vault] - Configuring the ssh secrets engine"
vault secrets enable -path=ssh ssh
vault write ssh/config/ca generate_signing_key=true
echo '
{
   "allow_user_certificates": true,
   "allowed_users": "*",
   "default_extensions": [{
      "permit-pty": ""
   }],
   "key_type": "ca",
   "key_id_format": "vault-{{role_name}}-{{token_display_name}}-{{public_key_hash}}",
   "default_user": "root",
   "ttl": "30m0s"
}' > ansiblerole.json
vault write ssh/roles/ansible @ansiblerole.json

# Policy
echo "[Setup-Vault] - Writing an ansible-ssh policy"
echo '
path "ssh/sign/ansible" {
capabilities = ["create", "update"]
}
path "kv/*" {
capabilities = ["read"]
}
' | vault policy write ansible-ssh -

# KV Secrets Engine
echo "[Setup-Vault] - Configuring the kv secrets engine"
vault secrets enable -path=kv -version=2 kv
ssh-keygen -t rsa -b 4096 -f ansible-key -q -N ""
vault kv put kv/ansible ssh-private-key=@ansible-key ssh-username=root

# AppRole Auth method
echo "[Setup-Vault] - Configuring the AppRole Auth method"
vault auth enable approle
vault write auth/approle/role/ansible \
  secret_id_ttl=24h \
  secret_id_num_uses=100 \
  token_num_uses=100 \
  token_ttl=24h \
  token_max_ttl=48h \
  policies="ansible-ssh"
vault read -format=json auth/approle/role/ansible/role-id > role.json
vault write -format=json -f auth/approle/role/ansible/secret-id > secretid.json
