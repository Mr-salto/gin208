# Define default target
.DEFAULT_GOAL := deploy


# Terraform targets
.PHONY: terraform-init
terraform-init:
	cd terraform && terraform init

.PHONY: terraform-plan
terraform-plan:
	cd terraform && terraform plan

.PHONY: terraform-apply
terraform-apply:
	cd terraform && terraform apply -auto-approve

.PHONY: terraform-destroy
terraform-destroy:
	cd terraform && terraform destroy -auto-approve

.PHONY: key-permission
key-permission:
	chmod 400 ../.ssh/private_key_gfetu_gin208
# Ansible target
.PHONY: ansible-frontend
ansible-frontend:
	ansible-playbook -i ./inventory.ini frontend_nginx.yml

.PHONY: certificate
certificate: 
	ansible-playbook -i ./inventory.ini issue_certificate.yml

.PHONY: ansible-backend
ansible-backend: 
	ansible-playbook -i ./inventory.ini backend_ffmpeg.yml

.PHONY: deploy-ansible
deploy-ansible: ansible-frontend certificate ansible-backend

# Combined target for deployment
.PHONY: deploy
deploy: terraform-init terraform-apply key-permission deploy-ansible


# terraform target
.PHONY: terraform
terraform: terraform-init terraform-apply key-permission
