# Synchronisation Upstream - Fork Nginx

## Pourquoi ce fork existe

Ce fork du role nginx a ete cree pour corriger un probleme de validation Ansible apparu avec les includes relatifs (`include fastcgi_params;`) dans les vhosts.

Concretement:

- le role upstream valide `nginx.conf` via `validate: nginx -t -c %s`,
- Ansible ecrit `%s` dans un dossier temporaire (`/tmp/...`),
- Nginx tente alors de resoudre les includes relatifs depuis ce dossier temporaire,
- ce qui provoque des erreurs du type `open() ".../fastcgi_params" failed (2: No such file or directory)`.

Le fork permet de garder un role stable en prod tout en conservant de la latitude pour des evolutions futures.

## Perimetre du fork

- Upstream source: `https://github.com/geerlingguy/ansible-role-nginx`
- Fork source: `https://github.com/CytadelHosting/ansible-role-nginx`
- Collection consommatrice: `cytadel.webserver`

Patch principal a conserver:

- validation Nginx robuste avec prefix explicite (`-p /etc/nginx/`) **ou**
- toute approche equivalente garantissant la resolution des includes pendant `validate`.

## Strategie de synchronisation

Objectif: recuperer les evolutions upstream sans perdre les patches Cytadel.

### 1) Recuperer upstream dans le fork

```bash
git clone git@github.com:CytadelHosting/ansible-role-nginx.git
cd ansible-role-nginx

git remote add upstream https://github.com/geerlingguy/ansible-role-nginx.git
git fetch --all --tags
```

### 2) Creer une branche de sync

```bash
git checkout main
git pull --ff-only origin main
git checkout -b chore/sync-upstream-<UPSTREAM_TAG>
```

Exemple: `chore/sync-upstream-3.3.1`.

### 3) Rejouer upstream

Choisir merge ou rebase selon ta politique:

```bash
# Option merge (lisible pour l'historique d'integration)
git merge --no-ff upstream/main

# Option alternative (lineaire)
# git rebase upstream/main
```

Si upstream tague une release precise:

```bash
git merge --no-ff <UPSTREAM_TAG>
```

### 4) Reappliquer/verifier les patches Cytadel

- verifier la zone de `tasks/main.yml` liee a `template.validate`,
- verifier les handlers/templating si upstream a bouge,
- s'assurer que le role reste compatible avec les vhosts de `apsys`.

### 5) Tests avant tag

Tests minimaux recommandes:

1. `ansible-lint` sur le role
2. run Ansible en `--check` sur un host de test
3. run reel sur un host de test
4. `nginx -t` OK
5. recharge nginx OK

## Convention de tagging du fork

Convention recommandee:

- `v<UPSTREAM>-cytadel.<N>`

Exemples:

- `v3.3.0-cytadel.1`
- `v3.3.0-cytadel.2`
- `v3.3.1-cytadel.1` (nouvelle base upstream, compteur local reset)

Creation/push:

```bash
git tag -a v3.3.0-cytadel.1 -m "Fork release based on upstream 3.3.0 (Cytadel patchset #1)"
git push origin v3.3.0-cytadel.1
```

## Integration dans la collection `cytadel.webserver`

Mettre a jour selon le mode choisi:

- mode submodule dynamique (`roles/...`),
- mode fige (`roles.lock.yaml`).

Exemple lockfile:

```yaml
roles:
  - role_name: "geerlingguy_nginx"
    src: "https://github.com/CytadelHosting/ansible-role-nginx.git"
    version: "v3.3.0-cytadel.1"
```

Puis:

```bash
make -f scripts/Makefile validate-lock
make -f scripts/Makefile build
```

## Checklist rapide de release

- [ ] sync upstream terminee
- [ ] patch Cytadel present et teste
- [ ] tag fork pousse
- [ ] `roles.lock.yaml` mis a jour
- [ ] build collection OK
- [ ] test AWX/CLI OK

