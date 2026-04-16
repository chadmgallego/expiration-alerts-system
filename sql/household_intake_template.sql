-- ============================================================
-- NEW HOUSEHOLD INTAKE TEMPLATE
-- Fill in values marked with <angle brackets>
-- Run in order: contacts → staff → documents
--
-- IMPORTANT: Always run the deduplication checks first before
-- inserting anything. This prevents duplicate households and
-- persons from being created when families resubmit the form.
-- ============================================================


-- ── PRE-INSERT DEDUPLICATION CHECKS ─────────────────────────
-- Run these BEFORE inserting anything.
-- If results come back, the household or person already exists.
-- Use the existing IDs instead of inserting new rows.

-- Check if household contact already exists
SELECT
    household_contact_id,
    name,
    email
FROM HOUSEHOLD_CONTACTS
WHERE name ILIKE '%<last name>%'
OR email ILIKE '%<contact@email.com>%';

-- Check if any of the persons already exist
-- (run once per person name in the submission)
SELECT
    s.personal_id,
    s.name,
    hc.name AS household_contact,
    hc.email
FROM STAFF_AND_DEP s
JOIN HOUSEHOLD_CONTACTS hc ON s.household_contact_id = hc.household_contact_id
WHERE s.name ILIKE '%<Person Full Name>%';

-- Check if any of the documents already exist for this person
-- (useful if someone is adding a new doc, not replacing an old one)
SELECT
    d.document_id,
    s.name AS person,
    d.document_type,
    d.expiration_date,
    d.last_alert_sent,
    d.last_alert_type,
    d.expired
FROM DOCUMENTS d
JOIN STAFF_AND_DEP s ON d.personal_id = s.personal_id
WHERE s.name ILIKE '%<Person Full Name>%';


-- ── DECISION LOGIC ───────────────────────────────────────────
-- After running the checks above, follow this logic:
--
-- Household contact already exists?
--   → SKIP Step 1. Use the existing household_contact_id.
--   → If email changed, run the UPDATE in Step 1b instead.
--
-- Person already exists?
--   → SKIP that person's INSERT in Step 2. Use their existing personal_id.
--   → If they are linked to a different household contact, run Step 2b.
--   → NOTE: If the new contact doesn't exist in HOUSEHOLD_CONTACTS yet,
--     run Step 1 to insert them first before reassigning in Step 2b.
--
-- Document already exists for that person?
--   → Use the upsert in Step 3 — it handles both new inserts and renewals automatically.
--   → On conflict, it updates the expiration date and resets alert fields.


-- ── STEP 1: Insert Household Contact ────────────────────────
-- Only run this if the household does NOT already exist.

INSERT INTO HOUSEHOLD_CONTACTS (name, email)
VALUES ('<Contact Full Name>', '<contact@email.com>');

-- Get the generated ID:
SELECT household_contact_id
FROM HOUSEHOLD_CONTACTS
WHERE email = '<contact@email.com>';

-- ── STEP 1b: Update contact email (if household exists but email changed)
-- UPDATE HOUSEHOLD_CONTACTS
-- SET email = '<new@email.com>'
-- WHERE household_contact_id = <existing_household_contact_id>;


-- ── STEP 2: Insert Staff & Dependents ───────────────────────
-- Only run per person if they do NOT already exist.
-- Replace <household_contact_id> with the ID from Step 1.

INSERT INTO STAFF_AND_DEP (name, household_contact_id)
VALUES ('<Person 1 Full Name>', <household_contact_id>);

INSERT INTO STAFF_AND_DEP (name, household_contact_id)
VALUES ('<Person 2 Full Name>', <household_contact_id>);

INSERT INTO STAFF_AND_DEP (name, household_contact_id)
VALUES ('<Person 3 Full Name>', <household_contact_id>);

-- Add or remove INSERT blocks above as needed.

-- Get personal_ids for Step 3:
SELECT personal_id, name
FROM STAFF_AND_DEP
WHERE household_contact_id = <household_contact_id>;

-- ── STEP 2b: Reassign person to a different household contact
-- NOTE: If the new contact doesn't exist in HOUSEHOLD_CONTACTS yet,
-- run Step 1 to insert them first before running this.
-- UPDATE STAFF_AND_DEP
-- SET household_contact_id = <correct_household_contact_id>
-- WHERE personal_id = <personal_id>;


-- ── STEP 3: Upsert Documents ──────────────────────────────────
-- Use upsert for all document inserts.
-- If the document already exists for this person → updates expiration date
-- and resets all alert fields so the new expiration cycle starts fresh.
-- If the document does not exist → inserts it as a new row.
--
-- Document types: 'Residence Card', 'Driver''s License',
--                 'National Health Insurance Card', 'U.S. Passport', or custom

-- Person 1 documents
INSERT INTO DOCUMENTS (personal_id, document_type, expiration_date)
VALUES (<person_1_id>, 'Residence Card', '<YYYY-MM-DD>')
ON CONFLICT (personal_id, document_type)
DO UPDATE SET
    expiration_date = EXCLUDED.expiration_date,
    last_alert_sent = NULL,
    last_alert_type = NULL,
    expired = FALSE;

INSERT INTO DOCUMENTS (personal_id, document_type, expiration_date)
VALUES (<person_1_id>, 'U.S. Passport', '<YYYY-MM-DD>')
ON CONFLICT (personal_id, document_type)
DO UPDATE SET
    expiration_date = EXCLUDED.expiration_date,
    last_alert_sent = NULL,
    last_alert_type = NULL,
    expired = FALSE;

INSERT INTO DOCUMENTS (personal_id, document_type, expiration_date)
VALUES (<person_1_id>, 'Driver''s License', '<YYYY-MM-DD>')
ON CONFLICT (personal_id, document_type)
DO UPDATE SET
    expiration_date = EXCLUDED.expiration_date,
    last_alert_sent = NULL,
    last_alert_type = NULL,
    expired = FALSE;

INSERT INTO DOCUMENTS (personal_id, document_type, expiration_date)
VALUES (<person_1_id>, 'National Health Insurance Card', '<YYYY-MM-DD>')
ON CONFLICT (personal_id, document_type)
DO UPDATE SET
    expiration_date = EXCLUDED.expiration_date,
    last_alert_sent = NULL,
    last_alert_type = NULL,
    expired = FALSE;

-- Person 2 documents
INSERT INTO DOCUMENTS (personal_id, document_type, expiration_date)
VALUES (<person_2_id>, 'Residence Card', '<YYYY-MM-DD>')
ON CONFLICT (personal_id, document_type)
DO UPDATE SET
    expiration_date = EXCLUDED.expiration_date,
    last_alert_sent = NULL,
    last_alert_type = NULL,
    expired = FALSE;

-- Add or remove INSERT blocks above as needed.


-- ── VERIFICATION ─────────────────────────────────────────────
-- Always run this after all inserts and updates to confirm
-- everything looks right before closing out the submission.

SELECT
    hc.name AS household_contact,
    hc.email,
    s.name AS person,
    d.document_type,
    d.expiration_date,
    d.expired,
    d.last_alert_sent,
    d.last_alert_type
FROM HOUSEHOLD_CONTACTS hc
JOIN STAFF_AND_DEP s ON hc.household_contact_id = s.household_contact_id
JOIN DOCUMENTS d ON s.personal_id = d.personal_id
WHERE hc.email = '<contact@email.com>'
ORDER BY s.name, d.expiration_date;
