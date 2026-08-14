# quadra-infra

Local Docker Compose environment for the Quadra platform (database, API, and frontend), and the future AWS infrastructure via Terraform.

## Installation

Requires Docker and Docker Compose.

For the full stack (database + API + frontend), clone the three repositories side by side:

```text
workspace/
  quadra-api/
  quadra-web/
  quadra-infra/
```

## Usage

Start just the database (to run the API or frontend locally, outside a container):

```bash
docker compose up -d
```

Publishes PostgreSQL on `localhost:5433`.

Start the full stack (database, API, and frontend in containers):

```bash
docker compose -f docker-compose-full.yml up --build
```

API at `http://localhost:3001`, frontend at `http://localhost:5173`.

## Examples

Check that the database is ready:

```bash
docker exec quadra-postgres pg_isready -U postgres -d quadra
```

Connect with psql:

```bash
psql postgresql://postgres:postgres@localhost:5433/quadra
```

## AWS infrastructure

The remote state bootstrap (S3 bucket and Terraform configuration) is located
in [`terraform/`](terraform/). See
[`docs/aws-setup-and-access.md`](docs/aws-setup-and-access.md) for the current
operational state and [`docs/ROADMAP.md`](docs/ROADMAP.md) for architecture
decisions.

## License

All rights reserved — see [LICENSE](LICENSE). Public for academic evaluation and portfolio purposes (TCC); not licensed for external use.
