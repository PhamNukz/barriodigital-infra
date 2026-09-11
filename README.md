# infra — BarrioDigital

Tres `docker-compose.yml` independientes, uno por dominio de infraestructura (sección 7 del caso): `apps/`, `mq/` (RabbitMQ) y `kafka/`. Se comunican entre sí por una red Docker compartida.

## Orden de arranque

```bash
docker network create barriodigital-net   # una sola vez

cd kafka && docker compose up -d
cd ../mq && docker compose up -d
cd ../apps
cp .env.example .env   # completa tus valores de Azure AD y Oracle
docker compose up -d --build
```

- **RabbitMQ Management UI:** http://localhost:15672 (guest/guest)
- **Kafka UI:** http://localhost:8085
- **Frontend:** http://localhost:4200
- **BFF:** http://localhost:8080

## Notas

- `apps/compose.yml` asume que este repo (`infra/`) está clonado como hermano de los otros 7 repos bajo la misma carpeta (igual que en este entorno de desarrollo: `BarrioDigital/{frontend-barriodigital, ms-barriodigital-*, infra}`). En EC2 real, cambia cada `build:` por `image: <ECR_URI>/<repo>:<tag>`.
- El caso (sección 7) solo menciona `requests-svc, catalog-svc, notify-svc, report-svc, audit-svc` en `ec2-apps`; agregué `bff` y `frontend` porque sin ellos el flujo `JWT → API Gateway → BFF → microservicio` no tiene por dónde entrar.
- Oracle **no** tiene su propio `compose.yml` en el caso — no tiene rol de "app" ni de "mq/kafka". Si decides correrlo en Docker en vez de Oracle Cloud, agrégalo a `apps/compose.yml` (imagen `gvenzl/oracle-free`) y ajusta `DB_HOST` a ese nombre de servicio.
- El cluster de RabbitMQ y el de Kafka son patrones simples para curso (ver comentarios `ponytail:` en cada archivo) — no llevan health-checks completos ni reintentos robustos de producción.

## Sin verificar end-to-end

Esta sesión no tiene Docker disponible, así que estos `compose.yml` están validados solo a nivel de **sintaxis YAML** (`yaml.safe_load` sobre los 3 archivos, sin errores). Nadie los ha corrido de verdad todavía — la primera vez que hagas `docker compose up`, es esperable tener que ajustar algún detalle (nombres de red, tiempos de espera del cluster de RabbitMQ, etc.).
