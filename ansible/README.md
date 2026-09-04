# Automacao Ansible Porto

Playbook para distribuir e configurar o banner operacional em servidores RHEL, Rocky Linux, AlmaLinux, CentOS Stream, SLES e openSUSE suportados.

## O que ele configura

- `/etc/profile.d/banner.sh`: banner exibido no login;
- `/usr/local/sbin/update-check.sh`: atualizador executado fora do login;
- `/var/cache/porto-banner/updates`: cache legivel por todos os usuarios;
- `/etc/cron.d/porto-update-check`: atualizacao agendada a cada hora.

O playbook nao aplica updates no sistema. Ele somente consulta os repositorios e atualiza o cache do banner.

## Pre-requisitos

- Ansible instalado no computador de controle;
- SSH funcionando nos servidores;
- usuario remoto com `sudo`;
- scripts-fonte disponiveis no controller em `/root/banner.sh` e `/root/update-check.sh`;
- inventario preenchido em `inventories/hosts.yml`.

Crie o inventario a partir do exemplo:

```bash
cp inventories/hosts.yml.example inventories/hosts.yml
```

Edite os hosts e usuarios antes de executar.

O playbook copia os scripts a partir do diretorio `/root` do servidor ponte. Para usar outra origem, sobrescreva as variaveis:

```bash
ansible-playbook site.yml \
	-e porto_banner_src=/outro/caminho/banner.sh \
	-e porto_update_check_src=/outro/caminho/update-check.sh
```

## Validar e executar

```bash
ansible-inventory --graph
ansible all -m ansible.builtin.ping
ansible-playbook --syntax-check site.yml
ansible-playbook site.yml --limit rocky-lab
```

Para executar em todos os servidores do grupo:

```bash
ansible-playbook site.yml
```

A cron atualiza o cache a cada hora. Para conferir na VM:

```bash
cat /etc/cron.d/porto-update-check
cat /var/cache/porto-banner/updates
```
