-- Digi Bank - Database creation script
-- Lab 2: Designing an initial monolithic architecture for Digi Bank with Jakarta EE
-- University of the Mountains - Cloud Computing Professional License

-- 1. Create the database
CREATE DATABASE digibank_db;

-- 2. Create the application user
CREATE USER digibank_user WITH PASSWORD 'digibank_pwd';

-- 3. Grant privileges
GRANT ALL PRIVILEGES ON DATABASE digibank_db TO digibank_user;

-- 4. Make the user the owner of the database
ALTER DATABASE digibank_db OWNER TO digibank_user;

-- 5. Connection verification
-- psql -U digibank_user -d digibank_db -h localhost

-- Note: The tables (customers, accounts, transactions) are generated automatically
-- by Hibernate (jakarta.persistence.schema-generation.database.action=update)
-- from the JPA entities on application startup.
