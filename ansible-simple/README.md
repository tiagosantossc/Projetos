# Deploy simples do banner Porto

Playbook Ansible para distribuir o banner e configurar a atualizacao do cache de updates via cron.

## Estrutura

```text
ansible-simple/
  inventory.ini.example
  site.yml
```

Os scripts usados pelo playbook ficam em `../scripts/`.

## Configurar inventario

```bash
cp inventory.ini.example inventory.ini
```

Edite `inventory.ini` com os servidores e usuarios corretos.

## Validar conexao

```bash
ansible -i inventory.ini linux -m ansible.builtin.ping
```

## Validar playbook

```bash
ansible-playbook -i inventory.ini --syntax-check site.yml
```

## Executar

Em um servidor:

```bash
ansible-playbook -i inventory.ini site.yml --limit rocky-lab
```

Em todos os servidores:

```bash
ansible-playbook -i inventory.ini site.yml
```

## Caminhos configurados no servidor

```text
/etc/profile.d/banner.sh
/usr/local/sbin/update-check.sh
/var/cache/porto-banner/updates
/etc/cron.d/porto-update-check
```

A cron executa o atualizador a cada hora. O playbook nao aplica atualizacoes no sistema; apenas consulta os repositorios e atualiza o cache usado pelo banner.
