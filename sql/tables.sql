-- Document Expiration Alert System
-- Database Schema (PostgreSQL)

CREATE TABLE HOUSEHOLD_CONTACTS (
    household_contact_id SERIAL PRIMARY KEY,
    name TEXT NOT NULL,
    email TEXT NOT NULL
);

CREATE TABLE STAFF_AND_DEP (
    personal_id SERIAL PRIMARY KEY,
    name TEXT NOT NULL,
    household_contact_id INTEGER REFERENCES HOUSEHOLD_CONTACTS(household_contact_id)
);

CREATE TABLE DOCUMENTS (
    document_id SERIAL PRIMARY KEY,
    personal_id INTEGER REFERENCES STAFF_AND_DEP(personal_id),
    document_type TEXT,
    expiration_date DATE,
    last_alert_sent DATE,
    last_alert_type INTEGER  -- stores 30, 60, or 90 depending on last alert tier sent
    expired BOOLEAN DEFAULT FALSE,  -- set to TRUE when expiration_date < CURRENT_DATE
);

-- NOTE: If adding these columns to an existing table, run:
-- ALTER TABLE DOCUMENTS ADD COLUMN expired BOOLEAN DEFAULT FALSE;
-- ALTER TABLE DOCUMENTS ADD CONSTRAINT unique_person_document UNIQUE (personal_id, document_type);
