# Digi Bank - Lab 2 Development Note

**Project:** Digi Bank - Modular Monolith with Jakarta EE
**Course:** UCC 122-1 Cloud Architecture - Lab 2
**University of the Mountains - Cloud Computing Professional License**

## 1. Order of development followed

The implementation followed a logical, dependency-driven order so that each module
could compile and be tested as soon as its dependencies were available:

1. **Environment preparation** - Installed JDK 17+, Apache Maven, PostgreSQL, WildFly
   33.0.2.Final, Git, and verified each with `java -version`, `mvn -version`,
   `git --version`, `psql --version`.
2. **PostgreSQL database** - Created the `digibank_db` database and the
   `digibank_user` application user with the required privileges.
3. **Multi-module Maven skeleton** - Created the `digibank-parent` aggregator POM and
   the seven module directories, then wrote every `pom.xml` (parent, shared, customer,
   account, transaction, compliance, index, app).
4. **Shared module** (`digibank-shared`) - Implemented `BaseEntity` (the JPA mapped
   superclass holding the generated `id`) and the `ApiResponse` DTO, because every
   business entity depends on `BaseEntity`.
5. **Business modules** - Implemented each module in dependency order:
   - `digibank-customer`: `Customer` entity, `CustomerRepository` (JPA/EJB),
     `CustomerService`, `CustomerResource`.
   - `digibank-account`: `Account` entity, `AccountService` (in-memory),
     `AccountResource`.
   - `digibank-transaction`: `Transaction` entity, `TransactionService` (in-memory),
     `TransactionResource`.
   - `digibank-compliance`: `ComplianceService` (amount <= 10000 rule),
     `ComplianceResource`.
   - `digibank-index`: `IndexServlet` forwarding to the styled `index.jsp` home page.
6. **Assembly module** (`digibank-app`) - Added the JAX-RS activation class
   `DigiBankApplication` (`@ApplicationPath("/api")`), the `persistence.xml` for the
   `digibankPU` persistence unit, and the WAR packaging with the `digibank-index`
   overlay.
7. **WildFly configuration** - Created the `org.postgresql` module (JDBC driver +
   `module.xml`), declared the `java:/jdbc/DigiBankDS` datasource and the PostgreSQL
   driver in `standalone.xml`.
8. **Build, package and deploy** - Ran `mvn clean install`, generated the WAR, and
   deployed it to WildFly (both by copying to `standalone/deployments/` and via the
   `wildfly-maven-plugin`).
9. **Functional verification** - Tested every REST endpoint with `curl`.
10. **JUnit tests** - Wrote `ComplianceServiceTest` and ran `mvn test`.
11. **Cucumber scenarios** - Wrote `compliance.feature`, `ComplianceSteps` and the
    `RunCucumberTest` runner.

## 2. Main difficulties encountered and solutions

1. **Entities not discovered by the persistence unit.**
   Because the entities live in separate dependency JARs (not in the WAR itself),
   Hibernate could not resolve them at runtime
   (`UnknownEntityException: Could not resolve root entity 'Customer'`).
   *Solution:* explicitly declared the entity classes with `<class>` elements in
   `persistence.xml`.

2. **Cucumber `@Suite` runner did not execute.**
   The `@Suite` annotation from `junit-platform-suite-api` alone is not enough; the
   suite engine must be present on the test classpath.
   *Solution:* added the `junit-platform-suite-engine` dependency.

3. **PostgreSQL port / instance mismatch.**
   The environment's PostgreSQL runs inside a Docker container exposed on port 5433
   (not the default 5432).
   *Solution:* pointed the WildFly datasource connection URL to
   `jdbc:postgresql://localhost:5433/digibank_db`.

4. **WildFly download interruption.**
   The initial WildFly archive download was truncated by a timeout, producing a
   corrupt zip.
   *Solution:* re-downloaded the full archive and verified it with `file` before
   extracting.

## 3. Final verification

- `mvn clean install` -> **BUILD SUCCESS** (8 modules).
- JUnit: 2/2 tests pass. Cucumber: 2/2 scenarios pass.
- All REST endpoints respond correctly and customer data persists to PostgreSQL
  across server restarts.
- Application deployed and accessible at `http://localhost:8080/digibank-app/`.
