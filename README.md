# Digi Bank - digibank-parent

**UCC 122-1 Cloud Architecture — Lab 2**
Designing an initial monolithic architecture (Legacy application) for **Digi Bank** with Jakarta EE.

University of the Mountains — Cloud Computing Professional License
Supervisor: Eng. Willy Damtchou | June 2026

## Overview

Digi Bank is a **modular monolith** banking application built with **Jakarta EE 10**, packaged as a
multi-module **Maven** project, deployed on **WildFly**, backed by **PostgreSQL**, and tested with
**JUnit** and **Cucumber (BDD)**.

## Modules

| Module              | Type | Responsibility                                        |
|---------------------|------|-------------------------------------------------------|
| `digibank-parent`   | pom  | Aggregator / parent POM                               |
| `digibank-shared`   | jar  | `BaseEntity`, `ApiResponse` (shared model & DTO)      |
| `digibank-customer` | jar  | Customer entity, repository, service, REST resource   |
| `digibank-account`  | jar  | Account entity, service, REST resource                |
| `digibank-transaction` | jar | Transaction entity, service, REST resource          |
| `digibank-compliance` | jar | Compliance service (amount validation), REST resource |
| `digibank-index`    | war  | `IndexServlet` + `index.jsp` home page                |
| `digibank-app`      | war  | Assembly module (JAX-RS app, persistence, WAR)        |

## Prerequisites

- JDK 17+ (project compiles with `source`/`target` 17)
- Apache Maven 3.9+
- PostgreSQL
- WildFly 33.0.2.Final
- Git

## Database setup

```sql
CREATE DATABASE digibank_db;
CREATE USER digibank_user WITH PASSWORD 'digibank_pwd';
GRANT ALL PRIVILEGES ON DATABASE digibank_db TO digibank_user;
```

See `sql/create_database.sql`.

## Build

```bash
mvn clean install
```

## Deploy to WildFly

Copy the generated WAR into the WildFly deployments folder:

```bash
cp digibank-app/target/digibank-app.war <WILDFLY_HOME>/standalone/deployments/
```

Or deploy via Maven (requires WildFly running with an `admin`/`admin` management user):

```bash
mvn -pl digibank-app wildfly:deploy
```

## REST endpoints

| Method | Endpoint                              | Description                    |
|--------|---------------------------------------|--------------------------------|
| GET    | `/api/index`                          | General information            |
| POST   | `/api/customers`                      | Create a customer              |
| GET    | `/api/customers`                      | List customers                 |
| POST   | `/api/accounts`                       | Create an account              |
| GET    | `/api/accounts`                       | List accounts                  |
| POST   | `/api/transactions`                   | Create a transaction           |
| GET    | `/api/transactions`                   | List transactions              |
| GET    | `/api/compliance/validate/{amount}`   | Validate a transaction amount  |

Base URL: `http://localhost:8080/digibank-app/api/`

## Tests

See **[TESTING.md](TESTING.md)**.

Start PostgreSQL/WildFly if needed, deploy, run JUnit/Cucumber, and print live API results:

```bash
./scripts/test-all.sh
```

Maven tests only (no server):

```bash
mvn test
```

- **JUnit** — `ComplianceServiceTest` (2 tests)
- **Cucumber** — `compliance.feature` (2 scenarios)

## WildFly configuration

- PostgreSQL JDBC module: `modules/system/layers/base/org/postgresql/main/`
- Datasource: `java:/jdbc/DigiBankDS` (see `standalone.xml`)

## Development note

See `NOTE.md` for the order of development followed and the main difficulties encountered.
