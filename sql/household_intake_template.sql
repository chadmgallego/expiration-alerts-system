-- ============================================================
-- NEW HOUSEHOLD INTAKE TEMPLATE
-- Fill in values marked with <angle brackets>
-- Run in order: contacts → staff → documents
-- ============================================================

-- ── STEP 1: Insert Household Contact ────────────────────────
-- Run this first. One row per household submission.

INSERT INTO HOUSEHOLD_CONTACTS (name, email)
VALUES ('<Contact Full Name>', '<contact@email.com>');

-- Capture the generated ID for use in Step 2
-- In Supabase SQL editor, run this after the insert above:
-- SELECT household_contact_id FROM HOUSEHOLD_CONTACTS WHERE email = '<contact@email.com>';


-- ── STEP 2: Insert Staff & Dependents ───────────────────────
-- One INSERT per person in the household.
-- Replace <household_contact_id> with the ID from Step 1.

INSERT INTO STAFF_AND_DEP (name, household_contact_id)
VALUES ('<Person 1 Full Name>', <household_contact_id>);

INSERT INTO STAFF_AND_DEP (name, household_contact_id)
VALUES ('<Person 2 Full Name>', <household_contact_id>);

INSERT INTO STAFF_AND_DEP (name, household_contact_id)
VALUES ('<Person 3 Full Name>', <household_contact_id>);

-- Add or remove INSERT blocks above as needed.

-- Capture personal_ids for use in Step 3:
-- SELECT personal_id, name FROM STAFF_AND_DEP WHERE household_contact_id = <household_contact_id>;


-- ── STEP 3: Insert Documents ─────────────────────────────────
-- One INSERT per document per person.
-- Replace <personal_id> with the ID from Step 2 for that person.
-- Document types: 'Residence Card', 'Driver\'s License',
--                 'National Health Insurance Card', 'U.S. Passport', or custom

-- Person 1 documents
INSERT INTO DOCUMENTS (personal_id, document_type, expiration_date)
VALUES (<person_1_id>, 'Residence Card', '<YYYY-MM-DD>');

INSERT INTO DOCUMENTS (personal_id, document_type, expiration_date)
VALUES (<person_1_id>, 'U.S. Passport', '<YYYY-MM-DD>');

INSERT INTO DOCUMENTS (personal_id, document_type, expiration_date)
VALUES (<person_1_id>, 'Driver''s License', '<YYYY-MM-DD>');

INSERT INTO DOCUMENTS (personal_id, document_type, expiration_date)
VALUES (<person_1_id>, 'National Health Insurance Card', '<YYYY-MM-DD>');

-- Person 2 documents
INSERT INTO DOCUMENTS (personal_id, document_type, expiration_date)
VALUES (<person_2_id>, 'Residence Card', '<YYYY-MM-DD>');

-- Add or remove INSERT blocks above as needed.


-- ── VERIFICATION ─────────────────────────────────────────────
-- Run this after all inserts to confirm everything looks right
-- before closing out the submission.

SELECT
    hc.name AS household_contact,
    hc.email,
    s.name AS person,
    d.document_type,
    d.expiration_date
FROM HOUSEHOLD_CONTACTS hc
JOIN STAFF_AND_DEP s ON hc.household_contact_id = s.household_contact_id
JOIN DOCUMENTS d ON s.personal_id = d.personal_id
WHERE hc.email = '<contact@email.com>'
ORDER BY s.name, d.expiration_date;
