# infra — BarrioDigital

Tres `docker-compose.yml` independientes, uno por EC2 (sección 7 del caso): `apps/` → `ec2-apps`, `mq/` → `ec2-mq`, `kafka/` → `ec2-kafka`. Se comunican por IP privada (ver tabla en `barriodigital-docs/AWS-Infraestructura.md`).

## Orden de arranque

Las EC2 privadas no tienen internet ni git: copia la carpeta desde tu PC (los alias `apps`/`mq`/`kafka`/`db` son de `~/.ssh/config`).

```bash
# 1. Kafka (ec2-kafka)
scp -r kafka kafka:~/ && ssh kafka
cd kafka && cp .env.example .env && docker compose up -d

# 2. RabbitMQ (ec2-mq)
scp -r mq mq:~/ && ssh mq
cd mq && cp -n .env.example .env   # completa RABBITMQ_DEFAULT_PASS y la cookie Erlang
                                  # -n: si el scp ya trajo un .env bueno, no lo pisa
docker compose up -d

# 3. Apps (ec2-apps)
scp -r apps apps:~/ && ssh apps
cd apps && cp .env.example .env   # completa Azure AD y contraseñas Oracle
docker compose up -d
```

Verificar desde `ec2-apps`: `nc -zv 10.0.1.8 1521`, `nc -zv 10.0.1.254 5672`, `nc -zv 10.0.1.29 9092`.

## `restart: always` (no cambiar a `unless-stopped`)

Los tres compose usan `restart: always` a propósito. Con `unless-stopped`, un
contenedor que quedó detenido porque se apagó el daemon **no** vuelve a arrancar
cuando el daemon revive — y eso es exactamente lo que pasa en el ciclo
stop/start de las EC2 del Learner Lab. Pasó en la práctica: tras reiniciar el
lab, RabbitMQ y Kafka quedaron abajo, y como `requests` publica eventos al
cambiar de estado, los cambios de estado empezaron a responder 503 (ver nota de
timeouts en `ms-barriodigital-requests`). Con `always`, los contenedores vuelven
solos al arrancar la instancia.

Si Kafka queda inestable al arrancar todo de golpe, los brokers pueden ganarle a
ZooKeeper (`NodeExistsException`): levanta primero `zk1 zk2 zk3`, espera ~20s y
después el resto.

- **RabbitMQ Management UI (los 2 nodos):** `ssh -L 15672:127.0.0.1:15672 -L 15673:127.0.0.1:15673 mq` → http://localhost:15672 (nodo 1) y http://localhost:15673 (nodo 2). Usuario: el `RABBITMQ_DEFAULT_USER` de `mq/.env`, ya no `guest/guest`. El forward termina en el loopback de `ec2-mq` (el alias `mq` salta por `apps`), asi que no cruza `sg-mq` y **no hace falta abrir 15673**
- **Kafka UI:** `ssh -L 8085:10.0.1.29:8085 apps` → http://localhost:8085
- **Frontend:** https://dnddhzpvgg.execute-api.us-east-1.amazonaws.com (el Gateway proxya `/` a ec2-apps:80; Entra exige https)
- **BFF:** https://dnddhzpvgg.execute-api.us-east-1.amazonaws.com/api (con JWT); directo `http://100.60.226.205:8080` solo para diagnóstico

Para desarrollo local (todo en una máquina), deja `RABBITMQ_HOST`, `KAFKA_BOOTSTRAP_SERVERS` y `KAFKA_PRIVATE_IP` en `host.docker.internal`.

## Cluster de RabbitMQ (`mq/`)

Dos nodos `rabbitmq:3.13-management` en la misma EC2. El cluster se forma solo:
`mq/rabbitmq.conf` declara los dos nodos con `peer_discovery_backend = classic_config`
y se monta igual en ambos contenedores (en `conf.d/`, para no chocar con la config
que el entrypoint del image genera a partir de `RABBITMQ_DEFAULT_USER/_PASS`).
`rabbitmq2` espera a que `rabbitmq1` este `healthy`: con `classic_config` el orden
de arranque decide quien forma el cluster y quien se suma.

**Credenciales.** `mq/.env` (desde `.env.example`) define usuario, password y la
cookie Erlang. Las tres **solo se aplican sobre un data dir virgen**: si los
volumenes ya tienen datos, no se crea nada y no hay aviso. Para el primer
arranque con credenciales nuevas:

```bash
docker compose down -v   # borra los DOS volumenes; borrar uno solo deja el cluster en desacuerdo
docker compose up -d
```

**Al cambiar el usuario hay que cambiarlo en los dos lados.** Los MS leen
`RABBITMQ_USER`/`RABBITMQ_PASSWORD` de `apps/.env`, que en produccion lo escribe
el secret `APPS_ENV` del `deploy.yml` — editar `apps/.env.example` no basta.
Orden: actualizar el secret `APPS_ENV` -> desplegar `mq` -> re-ejecutar `deploy`
(workflow_dispatch). Al reves, los MS quedan sin poder autenticar.

**El primer `up -d` tarda ~1 min y se queda esperando.** Es correcto: `rabbitmq2`
no arranca hasta que `rabbitmq1` esta `healthy`. Medido con volumenes virgenes:
nodo 1 listo en 46 s (36 de esos buscando al nodo 2, que por diseno todavia no
puede existir), nodo 2 en 12 s mas, los dos `healthy` a los 71 s. En `ec2-mq`
puede ser mas lento; el `start_period` de 120 s da margen de sobra.

**Verificacion** (es la evidencia del item 8 de EP4):

```bash
docker compose ps                                         # los 2 en Up (healthy)
docker compose exec rabbitmq1 rabbitmqctl cluster_status   # los 2 en Running Nodes
docker compose exec rabbitmq1 rabbitmq-diagnostics -q check_local_alarms
docker compose exec rabbitmq1 rabbitmq-diagnostics status | grep -A5 'Config files'
```

`check_local_alarms` importa porque la alarma de memoria **bloquea publishers en
silencio**: el watermark esta fijo en 512 MB por nodo (`mq/rabbitmq.conf`) para
que los dos quepan en los 2 GB de la t3.small. `Config files` confirma que el
bind mount se cargo de verdad.

**Pendiente en AWS:** `sg-mq` permite 5672 y 15672 desde `sg-apps`, pero no 5673.
Hace falta abrirlo cuando aterrice el `addresses` de failover (C8), que es cuando
los MS marcan el nodo 2 directo. Para las Management UI no se necesita: el tunel
de arriba termina en el loopback de `ec2-mq`.

## Notas

- `apps/compose.yml` asume que este repo (`infra/`) está clonado como hermano de los otros 7 repos bajo la misma carpeta (igual que en este entorno de desarrollo: `BarrioDigital/{frontend-barriodigital, ms-barriodigital-*, infra}`). En EC2 real, cambia cada `build:` por `image: <ECR_URI>/<repo>:<tag>`.
- El caso (sección 7) solo menciona `requests-svc, catalog-svc, notify-svc, report-svc, audit-svc` en `ec2-apps`; agregué `bff` y `frontend` porque sin ellos el flujo `JWT → API Gateway → BFF → microservicio` no tiene por dónde entrar.
- Oracle **no** tiene su propio `compose.yml` en el caso — no tiene rol de "app" ni de "mq/kafka". Si decides correrlo en Docker en vez de Oracle Cloud, agrégalo a `apps/compose.yml` (imagen `gvenzl/oracle-free`) y ajusta `DB_HOST` a ese nombre de servicio.
- El cluster de RabbitMQ y el de Kafka son patrones simples para curso (ver comentarios `ponytail:` en cada archivo) — no llevan health-checks completos ni reintentos robustos de producción.

## Sin verificar end-to-end

Esta sesión no tiene Docker disponible, así que estos `compose.yml` están validados solo a nivel de **sintaxis YAML** (`yaml.safe_load` sobre los 3 archivos, sin errores). Nadie los ha corrido de verdad todavía — la primera vez que hagas `docker compose up`, es esperable tener que ajustar algún detalle (nombres de red, tiempos de espera del cluster de RabbitMQ, etc.).
