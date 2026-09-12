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
cd mq && docker compose up -d

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

- **RabbitMQ Management UI:** `ssh -L 15672:10.0.1.254:15672 apps` → http://localhost:15672 (guest/guest)
- **Kafka UI:** `ssh -L 8085:10.0.1.29:8085 apps` → http://localhost:8085
- **Frontend:** https://dnddhzpvgg.execute-api.us-east-1.amazonaws.com (el Gateway proxya `/` a ec2-apps:80; Entra exige https)
- **BFF:** https://dnddhzpvgg.execute-api.us-east-1.amazonaws.com/api (con JWT); directo `http://100.60.226.205:8080` solo para diagnóstico

Para desarrollo local (todo en una máquina), deja `RABBITMQ_HOST`, `KAFKA_BOOTSTRAP_SERVERS` y `KAFKA_PRIVATE_IP` en `host.docker.internal`.

## Notas

- `apps/compose.yml` asume que este repo (`infra/`) está clonado como hermano de los otros 7 repos bajo la misma carpeta (igual que en este entorno de desarrollo: `BarrioDigital/{frontend-barriodigital, ms-barriodigital-*, infra}`). En EC2 real, cambia cada `build:` por `image: <ECR_URI>/<repo>:<tag>`.
- El caso (sección 7) solo menciona `requests-svc, catalog-svc, notify-svc, report-svc, audit-svc` en `ec2-apps`; agregué `bff` y `frontend` porque sin ellos el flujo `JWT → API Gateway → BFF → microservicio` no tiene por dónde entrar.
- Oracle **no** tiene su propio `compose.yml` en el caso — no tiene rol de "app" ni de "mq/kafka". Si decides correrlo en Docker en vez de Oracle Cloud, agrégalo a `apps/compose.yml` (imagen `gvenzl/oracle-free`) y ajusta `DB_HOST` a ese nombre de servicio.
- El cluster de RabbitMQ y el de Kafka son patrones simples para curso (ver comentarios `ponytail:` en cada archivo) — no llevan health-checks completos ni reintentos robustos de producción.

## Sin verificar end-to-end

Esta sesión no tiene Docker disponible, así que estos `compose.yml` están validados solo a nivel de **sintaxis YAML** (`yaml.safe_load` sobre los 3 archivos, sin errores). Nadie los ha corrido de verdad todavía — la primera vez que hagas `docker compose up`, es esperable tener que ajustar algún detalle (nombres de red, tiempos de espera del cluster de RabbitMQ, etc.).
